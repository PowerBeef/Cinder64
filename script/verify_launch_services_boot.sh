#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Cinder64"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DEFAULT_ROM="$ROOT_DIR/Super Mario 64 (USA)/Super Mario 64 (USA).z64"
ROM_PATH="${1:-$DEFAULT_ROM}"
VERIFY_ROOT="${2:-$(mktemp -d "${TMPDIR:-/tmp}/cinder64-smoke.XXXXXX")}"
APP_SUPPORT_ROOT="$VERIFY_ROOT/app-support"
RECENT_GAMES_FILE="$APP_SUPPORT_ROOT/recent-games.json"
RUNTIME_LOG_FILE="$APP_SUPPORT_ROOT/logs/runtime.log"
CRASH_REPORT_DIR="$HOME/Library/Logs/DiagnosticReports"
EXPECTED_LOG_LINE="Opened Super Mario 64 (USA) using"

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

/usr/bin/open -n -a "$APP_BUNDLE" "$ROM_PATH" --args --app-support-root "$APP_SUPPORT_ROOT"

for _ in $(seq 1 120); do
  if [[ "$(pgrep -x "$APP_NAME" | wc -l | tr -d ' ')" == "1" ]]; then
    break
  fi
  sleep 0.25
done

PROCESS_COUNT="$(pgrep -x "$APP_NAME" | wc -l | tr -d ' ')"
if [[ "$PROCESS_COUNT" != "1" ]]; then
  echo "Expected exactly one $APP_NAME process, found $PROCESS_COUNT." >&2
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

WINDOW_INFO="$(swift - <<'SWIFT'
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let cinderWindows = windows.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "Cinder64" &&
    (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0
}

print(cinderWindows.count)
for window in cinderWindows {
    let name = window[kCGWindowName as String] as? String ?? "untitled"
    print(name)
}
SWIFT
)"

WINDOW_COUNT="$(printf '%s\n' "$WINDOW_INFO" | sed -n '1p')"
if [[ "$WINDOW_COUNT" != "1" ]]; then
  echo "Expected exactly one visible Cinder64 window, found $WINDOW_COUNT." >&2
  printf '%s\n' "$WINDOW_INFO" >&2
  exit 1
fi

find "$CRASH_REPORT_DIR" -maxdepth 1 -type f -name 'Cinder64-*.ips' | sort >"$AFTER_CRASHES"
NEW_CRASHES="$(comm -13 "$BEFORE_CRASHES" "$AFTER_CRASHES" || true)"
if [[ -n "$NEW_CRASHES" ]]; then
  echo "A new Cinder64 crash report was created during boot:" >&2
  printf '%s\n' "$NEW_CRASHES" >&2
  exit 1
fi

echo "launch-services-boot:ok"
echo "app_bundle=$APP_BUNDLE"
echo "rom_path=$ROM_PATH"
echo "app_support_root=$APP_SUPPORT_ROOT"
echo "process_count=$PROCESS_COUNT"
echo "window_count=$WINDOW_COUNT"
echo "runtime_log=$RUNTIME_LOG_FILE"
echo "recent_games=$RECENT_GAMES_FILE"
