#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Cinder64"
BUNDLE_ID="com.patricedery.Cinder64"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

wait_for_no_running_app() {
  local attempts="${1:-40}"

  for _ in $(seq 1 "$attempts"); do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done

  return 1
}

ensure_app_is_stopped() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if wait_for_no_running_app; then
    return 0
  fi

  pkill -9 -x "$APP_NAME" >/dev/null 2>&1 || true
  if wait_for_no_running_app 20; then
    return 0
  fi

  echo "Timed out waiting for $APP_NAME to exit." >&2
  return 1
}

ensure_app_is_stopped

BRIDGE_LIBRARY="$("$ROOT_DIR/script/build_rust_bridge.sh" release)"

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

MOLTENVK_LIBRARY="$(resolve_optional_library CINDER64_MOLTENVK_LIBRARY molten-vk 'lib/libMoltenVK.dylib')"
FREETYPE_LIBRARY="$(resolve_optional_library CINDER64_FREETYPE_LIBRARY freetype 'lib/libfreetype.6.dylib')"
LIBPNG_LIBRARY="$(resolve_optional_library CINDER64_LIBPNG_LIBRARY libpng 'lib/libpng16.16.dylib')"

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BRIDGE_LIBRARY" "$APP_FRAMEWORKS/libcinder64_gopher64.dylib"
chmod +x "$APP_BINARY"
install_name_tool -id "@loader_path/libcinder64_gopher64.dylib" "$APP_FRAMEWORKS/libcinder64_gopher64.dylib"

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

bundle_support_library "$MOLTENVK_LIBRARY" "libMoltenVK.dylib"
bundle_support_library "$FREETYPE_LIBRARY" "libfreetype.6.dylib"
bundle_support_library "$LIBPNG_LIBRARY" "libpng16.16.dylib"

rewrite_dependency_if_present "$APP_FRAMEWORKS/libcinder64_gopher64.dylib" "$FREETYPE_LIBRARY" "libfreetype.6.dylib"
rewrite_dependency_if_present "$APP_FRAMEWORKS/libcinder64_gopher64.dylib" "$LIBPNG_LIBRARY" "libpng16.16.dylib"
rewrite_dependency_if_present "$APP_FRAMEWORKS/libfreetype.6.dylib" "$LIBPNG_LIBRARY" "libpng16.16.dylib"

adhoc_sign_if_present() {
  local target_path="$1"

  if [[ -e "$target_path" ]]; then
    codesign --force --sign - --timestamp=none "$target_path"
  fi
}

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

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_bundle_signatures() {
  test -f "$APP_FRAMEWORKS/libcinder64_gopher64.dylib"

  while IFS= read -r framework_path; do
    codesign --verify --verbose=2 "$framework_path"
  done < <(find "$APP_FRAMEWORKS" -maxdepth 1 -type f -name '*.dylib' | sort)

  codesign --verify --deep --verbose=2 "$APP_BUNDLE"
}

case "$MODE" in
  --prepare|prepare)
    verify_bundle_signatures
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    verify_bundle_signatures
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--prepare|--verify]" >&2
    exit 2
    ;;
esac
