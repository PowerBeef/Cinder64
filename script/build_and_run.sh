#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Cinder64"
BUNDLE_ID="com.patricedery.Cinder64"
MIN_SYSTEM_VERSION="15.0"
KEEP_RUN_BUNDLES=5

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
source "$ROOT_DIR/script/app_bundle_helpers.sh"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--prepare|--verify] [--print-bundle-path]" >&2
}

MODE="run"
PRINT_BUNDLE_PATH=0

while (($# > 0)); do
  case "$1" in
    run)
      MODE="run"
      ;;
    prepare|--prepare)
      MODE="prepare"
      ;;
    verify|--verify)
      MODE="verify"
      ;;
    debug|--debug)
      MODE="debug"
      ;;
    logs|--logs)
      MODE="logs"
      ;;
    telemetry|--telemetry)
      MODE="telemetry"
      ;;
    --print-bundle-path)
      PRINT_BUNDLE_PATH=1
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

if (( PRINT_BUNDLE_PATH )) && [[ "$MODE" != "prepare" ]]; then
  echo "--print-bundle-path is only supported with --prepare." >&2
  exit 2
fi

RUN_ID="$(cinder64_new_run_id)"
APP_BUNDLE="$(cinder64_prepare_run_bundle_directory "$RUN_ID")"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

resolve_optional_library() {
  local override_var="$1"
  local brew_formula="$2"
  local relative_path="$3"
  local override_value="${!override_var:-}"

  if [[ -n "$override_value" && -f "$override_value" ]]; then
    printf '%s\n' "$override_value"
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix="$(brew --prefix "$brew_formula" 2>/dev/null || true)"
    if [[ -n "$brew_prefix" && -f "$brew_prefix/$relative_path" ]]; then
      printf '%s\n' "$brew_prefix/$relative_path"
      return
    fi
  fi

  printf '\n'
}

bundle_support_library() {
  local source_path="$1"
  local target_name="$2"

  if [[ -n "$source_path" && -f "$source_path" ]]; then
    cp "$source_path" "$APP_FRAMEWORKS/$target_name"
  fi
}

rewrite_dependency_if_present() {
  local binary_path="$1"
  local original_dependency="$2"
  local bundled_name="$3"

  if [[ -z "$original_dependency" ]]; then
    return
  fi

  if [[ -f "$binary_path" ]] && /usr/bin/otool -L "$binary_path" | grep -Fq "$original_dependency"; then
    install_name_tool -change "$original_dependency" "@loader_path/$bundled_name" "$binary_path"
  fi
}

adhoc_sign_if_present() {
  local target_path="$1"

  if [[ -e "$target_path" ]]; then
    codesign --force --sign - --timestamp=none "$target_path" >&2
  fi
}

verify_bundle_signatures() {
  test -f "$APP_FRAMEWORKS/libcinder64_gopher64.dylib"

  while IFS= read -r framework_path; do
    codesign --verify --verbose=2 "$framework_path" >&2
  done < <(find "$APP_FRAMEWORKS" -maxdepth 1 -type f -name '*.dylib' | sort)

  codesign --verify --deep --verbose=2 "$APP_BUNDLE" >&2
}

prepare_bundle() {
  local bridge_library
  local moltenvk_library
  local freetype_library
  local libpng_library
  local build_binary

  bridge_library="$("$ROOT_DIR/script/build_rust_bridge.sh" release)"
  moltenvk_library="$(resolve_optional_library CINDER64_MOLTENVK_LIBRARY molten-vk 'lib/libMoltenVK.dylib')"
  freetype_library="$(resolve_optional_library CINDER64_FREETYPE_LIBRARY freetype 'lib/libfreetype.6.dylib')"
  libpng_library="$(resolve_optional_library CINDER64_LIBPNG_LIBRARY libpng 'lib/libpng16.16.dylib')"

  swift build >&2
  build_binary="$(swift build --show-bin-path)/$APP_NAME"

  mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS"
  cp "$build_binary" "$APP_BINARY"
  cp "$bridge_library" "$APP_FRAMEWORKS/libcinder64_gopher64.dylib"
  chmod +x "$APP_BINARY"
  install_name_tool -id "@loader_path/libcinder64_gopher64.dylib" "$APP_FRAMEWORKS/libcinder64_gopher64.dylib"

  bundle_support_library "$moltenvk_library" "libMoltenVK.dylib"
  bundle_support_library "$freetype_library" "libfreetype.6.dylib"
  bundle_support_library "$libpng_library" "libpng16.16.dylib"

  rewrite_dependency_if_present "$APP_FRAMEWORKS/libcinder64_gopher64.dylib" "$freetype_library" "libfreetype.6.dylib"
  rewrite_dependency_if_present "$APP_FRAMEWORKS/libcinder64_gopher64.dylib" "$libpng_library" "libpng16.16.dylib"
  rewrite_dependency_if_present "$APP_FRAMEWORKS/libfreetype.6.dylib" "$libpng_library" "libpng16.16.dylib"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>z64</string>
        <string>n64</string>
        <string>v64</string>
        <string>zip</string>
        <string>7z</string>
      </array>
      <key>CFBundleTypeName</key>
      <string>Nintendo 64 ROM</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
    </dict>
  </array>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

  while IFS= read -r framework_path; do
    adhoc_sign_if_present "$framework_path"
  done < <(find "$APP_FRAMEWORKS" -maxdepth 1 -type f -name '*.dylib' | sort)

  adhoc_sign_if_present "$APP_BINARY"
  adhoc_sign_if_present "$APP_BUNDLE"
  verify_bundle_signatures
  cinder64_update_latest_bundle_symlink "$APP_BUNDLE"
  cinder64_prune_run_bundles "$KEEP_RUN_BUNDLES" "$APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

launch_app_and_capture_pid() {
  open_app
  cinder64_wait_for_pid_for_bundle "$APP_BUNDLE" 120
}

prepare_bundle

case "$MODE" in
  prepare)
    if (( PRINT_BUNDLE_PATH )); then
      printf '%s\n' "$APP_BUNDLE"
    fi
    ;;
  run)
    open_app
    ;;
  debug)
    lldb -- "$APP_BINARY"
    ;;
  logs)
    launched_pid="$(launch_app_and_capture_pid)"
    /usr/bin/log stream --info --style compact --process "$launched_pid"
    ;;
  telemetry)
    launched_pid="$(launch_app_and_capture_pid)"
    /usr/bin/log stream --info --style compact --process "$launched_pid" --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  verify)
    launched_pid="$(launch_app_and_capture_pid)"
    if ! cinder64_pid_is_alive "$launched_pid"; then
      echo "Expected launched Cinder64 PID to stay alive, but PID $launched_pid exited." >&2
      exit 1
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
