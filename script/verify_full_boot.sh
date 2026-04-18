#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/boot_key_profiles.sh"

APP_NAME="Cinder64"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DEFAULT_ROM="$ROOT_DIR/Super Mario 64 (USA)/Super Mario 64 (USA).z64"
ROM_PATH="${1:-$DEFAULT_ROM}"
VERIFY_ROOT="${2:-$(mktemp -d "${TMPDIR:-/tmp}/cinder64-fullboot.XXXXXX")}"
APP_SUPPORT_ROOT="$VERIFY_ROOT/app-support"
RUNTIME_LOG_FILE="$APP_SUPPORT_ROOT/logs/runtime.log"
RECENT_GAMES_FILE="$APP_SUPPORT_ROOT/recent-games.json"
CRASH_REPORT_DIR="$HOME/Library/Logs/DiagnosticReports"
READY_LINE="Opened Super Mario 64 (USA) using"
KEY_PROFILE_NAME="${CINDER64_BOOT_KEY_PROFILE:-smoke}"
SCRIPTED_KEYS="$(resolve_scripted_key_profile "$KEY_PROFILE_NAME")"
#
# NOTE on screenshots: calling `screencapture -l <windowID>` against this app while
# gopher64 is running causes parallel-rdp's check_callback() to observe `emu_running
# == false` on the next VI tick and exit cpu::run() — which flips the bridge's
# status.active to false and drops any subsequent set_keyboard_key() injections.
# Until that interaction is understood (likely an SDL window event fired by the
# window-server capture path), this smoke test relies on log-based assertions
# only. Manual visual verification: run `./script/build_and_run.sh`, press Return
# once the logo has finished zooming, watch the file-select screen appear.

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

# Let the scripted-keys timeline play through; last step is at +7.1s, leave breathing
# room for the Lakitu intro to wind down so we can sample plenty of frame_count ticks.
sleep 15

assert_exactly_one_window

assert_log() {
  local needle="$1"
  if ! grep -Fq "$needle" "$RUNTIME_LOG_FILE"; then
    echo "Expected line in runtime log but did not find it: $needle" >&2
    echo "--- runtime.log tail ---" >&2
    tail -60 "$RUNTIME_LOG_FILE" >&2
    exit 1
  fi
}

assert_log "scripted-keys armed count=4"
assert_log "scripted-key step 1 executed scancode=40 pressed=true"
assert_log "scripted-key step 2 executed scancode=40 pressed=false"
assert_log "scripted-key step 3 executed scancode=225 pressed=true"
assert_log "scripted-key step 4 executed scancode=225 pressed=false"
assert_log "scripted-keys playback completed"

if grep -Fq "setKeyboardKey failed" "$RUNTIME_LOG_FILE"; then
  echo "At least one scripted keystroke was rejected by the bridge:" >&2
  grep -F "setKeyboardKey failed" "$RUNTIME_LOG_FILE" >&2
  exit 1
fi

FRAME_COUNTS="$(grep -E 'frame_count=[0-9]+' "$RUNTIME_LOG_FILE" | sed -E 's/.*frame_count=([0-9]+).*/\1/')"
if [[ -z "$FRAME_COUNTS" ]]; then
  echo "No frame_count telemetry was logged by the bridge." >&2
  exit 1
fi

FIRST_FRAME="$(printf '%s\n' "$FRAME_COUNTS" | head -n1)"
LAST_FRAME="$(printf '%s\n' "$FRAME_COUNTS" | tail -n1)"
SAMPLE_COUNT="$(printf '%s\n' "$FRAME_COUNTS" | wc -l | tr -d ' ')"

if ! printf '%s\n' "$FRAME_COUNTS" | awk 'NR==1{p=$1; next} $1 <= p {exit 1} {p=$1}'; then
  echo "Frame counter did not advance monotonically:" >&2
  printf '%s\n' "$FRAME_COUNTS" >&2
  exit 1
fi

# With the app frontmost and no external window capture, pump_events fires at the
# full 60 Hz, so across 15 seconds we expect ≥900 ticks in total. A significantly
# smaller delta means the emulation thread exited before playback finished.
if (( SAMPLE_COUNT < 8 || LAST_FRAME - FIRST_FRAME < 600 )); then
  echo "Frame counter did not advance far enough: first=$FIRST_FRAME last=$LAST_FRAME samples=$SAMPLE_COUNT." >&2
  exit 1
fi

if [[ ! -f "$RECENT_GAMES_FILE" ]] || ! grep -Fq '"displayName" : "Super Mario 64 (USA)"' "$RECENT_GAMES_FILE"; then
  echo "The repo ROM was not recorded in recent-games.json after boot." >&2
  exit 1
fi

find "$CRASH_REPORT_DIR" -maxdepth 1 -type f -name 'Cinder64-*.ips' | sort >"$AFTER_CRASHES"
NEW_CRASHES="$(comm -13 "$BEFORE_CRASHES" "$AFTER_CRASHES" || true)"
if [[ -n "$NEW_CRASHES" ]]; then
  echo "A new Cinder64 crash report was created during the full-boot run:" >&2
  printf '%s\n' "$NEW_CRASHES" >&2
  exit 1
fi

echo "full-boot:ok"
echo "rom_path=$ROM_PATH"
echo "app_support_root=$APP_SUPPORT_ROOT"
echo "key_profile=$KEY_PROFILE_NAME"
echo "frame_count_first=$FIRST_FRAME"
echo "frame_count_last=$LAST_FRAME"
echo "frame_count_samples=$SAMPLE_COUNT"
echo "runtime_log=$RUNTIME_LOG_FILE"
