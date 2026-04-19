#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Cinder64"
DIST_DIR="$ROOT_DIR/dist"
source "$ROOT_DIR/script/app_bundle_helpers.sh"

DEFAULT_ROM="$ROOT_DIR/Super Mario 64 (USA)/Super Mario 64 (USA).z64"
ROM_PATH="${1:-$DEFAULT_ROM}"
VERIFY_ROOT="${2:-$(mktemp -d "${TMPDIR:-/tmp}/cinder64-smoke.XXXXXX")}"
APP_SUPPORT_ROOT="$VERIFY_ROOT/app-support"
RECENT_GAMES_FILE="$APP_SUPPORT_ROOT/recent-games.json"
RUNTIME_LOG_FILE="$APP_SUPPORT_ROOT/logs/runtime.log"
CRASH_REPORT_DIR="$HOME/Library/Logs/DiagnosticReports"
EXPECTED_LOG_LINE="Opened Super Mario 64 (USA) using"

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

mkdir -p "$APP_SUPPORT_ROOT"
cinder64_capture_crash_snapshot "$BEFORE_CRASHES" "$CRASH_REPORT_DIR"

/usr/bin/open -n -a "$APP_BUNDLE" "$ROM_PATH" --args --app-support-root "$APP_SUPPORT_ROOT"

if ! LAUNCHED_PID="$(cinder64_wait_for_pid_for_bundle "$APP_BUNDLE" 120)"; then
  echo "Timed out waiting for the launched $APP_NAME process." >&2
  exit 1
fi

if ! cinder64_pid_is_alive "$LAUNCHED_PID"; then
  echo "Launched PID $LAUNCHED_PID exited before boot verification completed." >&2
  exit 1
fi

LOG_READY=0
for _ in $(seq 1 240); do
  if [[ -f "$RECENT_GAMES_FILE" ]] && grep -Fq '"displayName" : "Super Mario 64 (USA)"' "$RECENT_GAMES_FILE"; then
    if [[ ! -f "$RUNTIME_LOG_FILE" ]] || ! grep -Fq "$EXPECTED_LOG_LINE" "$RUNTIME_LOG_FILE"; then
      echo "Recent games were recorded before the runtime reported readiness." >&2
      exit 1
    fi
  fi

  if [[ -f "$RUNTIME_LOG_FILE" ]] && grep -Fq "$EXPECTED_LOG_LINE" "$RUNTIME_LOG_FILE"; then
    LOG_READY=1
    break
  fi

  if ! cinder64_pid_is_alive "$LAUNCHED_PID"; then
    echo "Launched PID $LAUNCHED_PID exited before the readiness log appeared." >&2
    exit 1
  fi

  sleep 0.25
done

if [[ "$LOG_READY" != "1" ]]; then
  echo "Timed out waiting for the runtime readiness log." >&2
  exit 1
fi

if [[ ! -f "$RECENT_GAMES_FILE" ]] || ! grep -Fq '"displayName" : "Super Mario 64 (USA)"' "$RECENT_GAMES_FILE"; then
  echo "The repo ROM was not recorded in recent-games.json after boot." >&2
  exit 1
fi

WINDOW_INFO="$(cinder64_window_info_for_pid "$LAUNCHED_PID")"
WINDOW_COUNT="$(printf '%s\n' "$WINDOW_INFO" | sed -n '1p')"
if [[ "$WINDOW_COUNT" != "1" ]]; then
  echo "Expected exactly one visible window for launched PID $LAUNCHED_PID, found $WINDOW_COUNT." >&2
  printf '%s\n' "$WINDOW_INFO" >&2
  exit 1
fi

cinder64_capture_crash_snapshot "$AFTER_CRASHES" "$CRASH_REPORT_DIR"
NEW_CRASHES="$(cinder64_matching_new_crashes_for_pid "$BEFORE_CRASHES" "$AFTER_CRASHES" "$LAUNCHED_PID")"
if [[ -n "$NEW_CRASHES" ]]; then
  echo "A new Cinder64 crash report was created for PID $LAUNCHED_PID during boot:" >&2
  printf '%s\n' "$NEW_CRASHES" >&2
  exit 1
fi

echo "launch-services-boot:ok"
echo "bundle_path=$APP_BUNDLE"
echo "launched_pid=$LAUNCHED_PID"
echo "rom_path=$ROM_PATH"
echo "app_support_root=$APP_SUPPORT_ROOT"
echo "window_count=$WINDOW_COUNT"
echo "runtime_log=$RUNTIME_LOG_FILE"
echo "recent_games=$RECENT_GAMES_FILE"
