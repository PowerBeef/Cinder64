#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/boot_key_profiles.sh"

APP_NAME="Cinder64"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DEFAULT_ROM="$ROOT_DIR/Super Mario 64 (USA)/Super Mario 64 (USA).z64"
ROM_PATH="${1:-$DEFAULT_ROM}"
VERIFY_ROOT="${2:-$(mktemp -d "${TMPDIR:-/tmp}/cinder64-visualboot.XXXXXX")}"
APP_SUPPORT_ROOT="$VERIFY_ROOT/app-support"
RUNTIME_LOG_FILE="$APP_SUPPORT_ROOT/logs/runtime.log"
RECENT_GAMES_FILE="$APP_SUPPORT_ROOT/recent-games.json"
CRASH_REPORT_DIR="$HOME/Library/Logs/DiagnosticReports"
READY_LINE="Opened Super Mario 64 (USA) using"
KEY_PROFILE_NAME="${CINDER64_BOOT_KEY_PROFILE:-visual}"
SCRIPTED_KEYS="$(resolve_scripted_key_profile "$KEY_PROFILE_NAME")"

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

assert_exactly_one_window() {
  local count
  count="$(swift - <<'SWIFT'
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let cinderWindows = windows.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "Cinder64" &&
    (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0
}
print(cinderWindows.count)
SWIFT
)"
  if [[ "$count" != "1" ]]; then
    echo "Expected exactly one visible Cinder64 window, found $count." >&2
    return 1
  fi
}

if [[ ! -f "$ROM_PATH" ]]; then
  echo "ROM not found: $ROM_PATH" >&2
  exit 1
fi

"$ROOT_DIR/script/build_and_run.sh" --prepare >/dev/null

ensure_app_is_stopped
mkdir -p "$APP_SUPPORT_ROOT"

BEFORE_CRASHES="$(mktemp "${TMPDIR:-/tmp}/cinder64-crashes-before.XXXXXX")"
AFTER_CRASHES="$(mktemp "${TMPDIR:-/tmp}/cinder64-crashes-after.XXXXXX")"

cleanup() {
  ensure_app_is_stopped >/dev/null 2>&1 || true
  rm -f "$BEFORE_CRASHES" "$AFTER_CRASHES"
}

trap cleanup EXIT

find "$CRASH_REPORT_DIR" -maxdepth 1 -type f -name 'Cinder64-*.ips' | sort >"$BEFORE_CRASHES"

/usr/bin/open -n -a "$APP_BUNDLE" "$ROM_PATH" --args \
  --app-support-root "$APP_SUPPORT_ROOT" \
  --scripted-keys "$SCRIPTED_KEYS"

for _ in $(seq 1 240); do
  if [[ -f "$RUNTIME_LOG_FILE" ]] && grep -Fq "$READY_LINE" "$RUNTIME_LOG_FILE"; then
    break
  fi
  sleep 0.25
done

if ! grep -Fq "$READY_LINE" "$RUNTIME_LOG_FILE" 2>/dev/null; then
  echo "Timed out waiting for the runtime readiness log." >&2
  exit 1
fi

sleep 18
assert_exactly_one_window

if [[ ! -f "$RECENT_GAMES_FILE" ]] || ! grep -Fq '"displayName" : "Super Mario 64 (USA)"' "$RECENT_GAMES_FILE"; then
  echo "The repo ROM was not recorded in recent-games.json after visual boot." >&2
  exit 1
fi

if grep -Fq "setKeyboardKey failed" "$RUNTIME_LOG_FILE"; then
  echo "At least one scripted keystroke was rejected during the visual boot pass:" >&2
  grep -F "setKeyboardKey failed" "$RUNTIME_LOG_FILE" >&2
  exit 1
fi

find "$CRASH_REPORT_DIR" -maxdepth 1 -type f -name 'Cinder64-*.ips' | sort >"$AFTER_CRASHES"
NEW_CRASHES="$(comm -13 "$BEFORE_CRASHES" "$AFTER_CRASHES" || true)"
if [[ -n "$NEW_CRASHES" ]]; then
  echo "A new Cinder64 crash report was created during the visual boot run:" >&2
  printf '%s\n' "$NEW_CRASHES" >&2
  exit 1
fi

trap - EXIT
rm -f "$BEFORE_CRASHES" "$AFTER_CRASHES"

echo "visual-boot:ready"
echo "rom_path=$ROM_PATH"
echo "app_support_root=$APP_SUPPORT_ROOT"
echo "key_profile=$KEY_PROFILE_NAME"
echo "runtime_log=$RUNTIME_LOG_FILE"
echo "expected_checkpoints=title-visible,start-accepted,file-select-or-lakitu,in-game-scene"
echo "expected_resize_checkpoints=drag-resize-for-5s,no-repeated-black-flicker,final-frame-recovers,input-still-works"
echo "fullscreen_note=Live fullscreen changes are intentionally deferred while a ROM is active during this stabilization pass."
echo "app_process_note=The app is still running for foreground inspection."
