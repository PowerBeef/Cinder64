#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/boot_key_profiles.sh"

APP_NAME="Cinder64"
DIST_DIR="$ROOT_DIR/dist"
source "$ROOT_DIR/script/app_bundle_helpers.sh"

DEFAULT_ROM="$ROOT_DIR/Super Mario 64 (USA)/Super Mario 64 (USA).z64"
ROM_PATH="${1:-$DEFAULT_ROM}"
VERIFY_ROOT="${2:-$(mktemp -d "${TMPDIR:-/tmp}/cinder64-visualboot.XXXXXX")}"
case "$VERIFY_ROOT" in
  /*) ;;
  *) VERIFY_ROOT="$ROOT_DIR/$VERIFY_ROOT" ;;
esac
APP_SUPPORT_ROOT="$VERIFY_ROOT/app-support"
RUNTIME_LOG_FILE="$APP_SUPPORT_ROOT/logs/runtime.log"
RECENT_GAMES_FILE="$APP_SUPPORT_ROOT/recent-games.json"
CRASH_REPORT_DIR="$HOME/Library/Logs/DiagnosticReports"
READY_LINE="Opened Super Mario 64 (USA) using"
KEY_PROFILE_NAME="${CINDER64_BOOT_KEY_PROFILE:-visual}"
SCRIPTED_KEYS="$(resolve_scripted_key_profile "$KEY_PROFILE_NAME")"

assert_exactly_one_window_for_pid() {
  local window_info
  local window_count
  local pid="$1"

  window_info="$(cinder64_window_info_for_pid "$pid")"
  window_count="$(printf '%s\n' "$window_info" | sed -n '1p')"
  if [[ "$window_count" != "1" ]]; then
    echo "Expected exactly one visible window for launched PID $pid, found $window_count." >&2
    printf '%s\n' "$window_info" >&2
    return 1
  fi
}

if [[ ! -f "$ROM_PATH" ]]; then
  echo "ROM not found: $ROM_PATH" >&2
  exit 1
fi

APP_BUNDLE="$("$ROOT_DIR/script/build_and_run.sh" --prepare --print-bundle-path)"
LAUNCHED_PID=""
BEFORE_CRASHES="$(mktemp "${TMPDIR:-/tmp}/cinder64-crashes-before.XXXXXX")"
AFTER_CRASHES="$(mktemp "${TMPDIR:-/tmp}/cinder64-crashes-after.XXXXXX")"

cleanup() {
  if [[ -n "${LAUNCHED_PID:-}" ]]; then
    cinder64_stop_pid "$LAUNCHED_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$BEFORE_CRASHES" "$AFTER_CRASHES"
}

trap cleanup EXIT

rm -rf "$APP_SUPPORT_ROOT"
mkdir -p "$APP_SUPPORT_ROOT"
cinder64_capture_crash_snapshot "$BEFORE_CRASHES" "$CRASH_REPORT_DIR"

/usr/bin/open -n -a "$APP_BUNDLE" "$ROM_PATH" --args \
  --app-support-root "$APP_SUPPORT_ROOT" \
  --scripted-keys "$SCRIPTED_KEYS"

if ! LAUNCHED_PID="$(cinder64_wait_for_pid_for_bundle "$APP_BUNDLE" 120)"; then
  echo "Timed out waiting for the launched $APP_NAME process." >&2
  exit 1
fi

for _ in $(seq 1 240); do
  if [[ -f "$RUNTIME_LOG_FILE" ]] && grep -Fq "$READY_LINE" "$RUNTIME_LOG_FILE"; then
    break
  fi

  if ! cinder64_pid_is_alive "$LAUNCHED_PID"; then
    echo "Launched PID $LAUNCHED_PID exited before the readiness log appeared." >&2
    exit 1
  fi

  sleep 0.25
done

if ! grep -Fq "$READY_LINE" "$RUNTIME_LOG_FILE" 2>/dev/null; then
  echo "Timed out waiting for the runtime readiness log." >&2
  exit 1
fi

sleep 18
assert_exactly_one_window_for_pid "$LAUNCHED_PID"

if [[ ! -f "$RECENT_GAMES_FILE" ]] || ! grep -Fq '"displayName" : "Super Mario 64 (USA)"' "$RECENT_GAMES_FILE"; then
  echo "The repo ROM was not recorded in recent-games.json after visual boot." >&2
  exit 1
fi

if grep -Fq "setKeyboardKey failed" "$RUNTIME_LOG_FILE"; then
  echo "At least one scripted keystroke was rejected during the visual boot pass:" >&2
  grep -F "setKeyboardKey failed" "$RUNTIME_LOG_FILE" >&2
  exit 1
fi

cinder64_capture_crash_snapshot "$AFTER_CRASHES" "$CRASH_REPORT_DIR"
NEW_CRASHES="$(cinder64_matching_new_crashes_for_pid "$BEFORE_CRASHES" "$AFTER_CRASHES" "$LAUNCHED_PID")"
if [[ -n "$NEW_CRASHES" ]]; then
  echo "A new Cinder64 crash report was created for PID $LAUNCHED_PID during the visual boot run:" >&2
  printf '%s\n' "$NEW_CRASHES" >&2
  exit 1
fi

trap - EXIT
rm -f "$BEFORE_CRASHES" "$AFTER_CRASHES"

echo "visual-boot:ready"
echo "bundle_path=$APP_BUNDLE"
echo "launched_pid=$LAUNCHED_PID"
echo "rom_path=$ROM_PATH"
echo "app_support_root=$APP_SUPPORT_ROOT"
echo "key_profile=$KEY_PROFILE_NAME"
echo "runtime_log=$RUNTIME_LOG_FILE"
echo "expected_checkpoints=title-visible,start-accepted,file-select-or-lakitu,in-game-scene"
echo "expected_resize_checkpoints=drag-resize-for-5s,no-repeated-black-flicker,final-frame-recovers,input-still-works"
echo "fullscreen_note=Live fullscreen changes are intentionally deferred while a ROM is active during this stabilization pass."
echo "app_process_note=The app is still running for foreground inspection."
