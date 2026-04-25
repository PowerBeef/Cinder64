#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Cinder64"
DIST_DIR="$ROOT_DIR/dist"
source "$ROOT_DIR/script/app_bundle_helpers.sh"

DEFAULT_ROM="$ROOT_DIR/Roms/Super Mario 64 (USA).z64"
FALLBACK_ROM="$ROOT_DIR/Super Mario 64 (USA)/Super Mario 64 (USA).z64"
ROM_PATH=""
DESTRUCTIVE_CLOSE=0

usage() {
  cat >&2 <<'USAGE'
usage: script/verify_toolbar_controls.sh --rom <path> [--destructive-close]

Boots Cinder64 with an isolated app-support root, exercises gameplay toolbar
buttons through Accessibility, and checks that no Cinder64 crash report appears.
The destructive close path is opt-in because it stops the booted ROM.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rom)
      ROM_PATH="${2:-}"
      shift 2
      ;;
    --destructive-close)
      DESTRUCTIVE_CLOSE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$ROM_PATH" ]]; then
  if [[ -f "$DEFAULT_ROM" ]]; then
    ROM_PATH="$DEFAULT_ROM"
  else
    ROM_PATH="$FALLBACK_ROM"
  fi
fi

if [[ ! -f "$ROM_PATH" ]]; then
  echo "ROM not found: $ROM_PATH" >&2
  exit 1
fi

VERIFY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cinder64-toolbar.XXXXXX")"
APP_SUPPORT_ROOT="$VERIFY_ROOT/app-support"
RUNTIME_LOG_FILE="$APP_SUPPORT_ROOT/logs/runtime.log"
CRASH_REPORT_DIR="$HOME/Library/Logs/DiagnosticReports"
READY_LINE="Opened "

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

/usr/bin/open -n -a "$APP_BUNDLE" "$ROM_PATH" --args \
  --app-support-root "$APP_SUPPORT_ROOT"

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

osascript - "$DESTRUCTIVE_CLOSE" <<'APPLESCRIPT'
on failSmoke(message)
    error message number 1
end failSmoke

on elementText(candidate)
    tell application "System Events"
        set candidateText to ""
        try
            set candidateName to name of candidate
            if candidateName is not missing value then set candidateText to candidateName as text
        end try
        if candidateText is "" then
            try
                set candidateDescription to description of candidate
                if candidateDescription is not missing value then set candidateText to candidateDescription as text
            end try
        end if
        return candidateText
    end tell
end elementText

on activateCinder64()
    try
        tell application id "com.patricedery.Cinder64" to activate
    end try
    tell application "System Events"
        tell process "Cinder64"
            set frontmost to true
        end tell
    end tell
    delay 0.25
end activateCinder64

on widenMainWindow()
    tell application "System Events"
        tell process "Cinder64"
            repeat with candidateWindow in windows
                try
                    if subrole of candidateWindow is "AXStandardWindow" then
                        set size of candidateWindow to {1280, 820}
                        return
                    end if
                end try
            end repeat
        end tell
    end tell
end widenMainWindow

on toolbarButtonNameStartsWith(prefix)
    tell application "System Events"
        tell process "Cinder64"
            repeat with candidateWindow in windows
                try
                    repeat with candidateToolbar in toolbars of candidateWindow
                        repeat with candidate in buttons of candidateToolbar
                            set candidateName to my elementText(candidate)
                            if candidateName starts with prefix then return true
                        end repeat
                    end repeat
                end try
            end repeat
        end tell
    end tell
    return false
end toolbarButtonNameStartsWith

on waitForToolbarButton(prefix)
    repeat with attempt from 1 to 80
        if toolbarButtonNameStartsWith(prefix) then return
        delay 0.25
    end repeat
    failSmoke("Timed out waiting for toolbar button starting with " & prefix)
end waitForToolbarButton

on clickToolbarButton(prefix)
    tell application "System Events"
        tell process "Cinder64"
            set frontmost to true
            repeat with attempt from 1 to 80
                repeat with candidateWindow in windows
                    try
                        repeat with candidateToolbar in toolbars of candidateWindow
                            repeat with candidate in buttons of candidateToolbar
                                set candidateName to my elementText(candidate)
                                if candidateName starts with prefix then
                                    set candidatePosition to position of candidate
                                    set candidateSize to size of candidate
                                    click at {((item 1 of candidatePosition) + ((item 1 of candidateSize) / 2)), ((item 2 of candidatePosition) + ((item 2 of candidateSize) / 2))}
                                    return
                                end if
                            end repeat
                        end repeat
                    end try
                end repeat
                delay 0.25
            end repeat
        end tell
    end tell
    failSmoke("Timed out clicking toolbar button starting with " & prefix)
end clickToolbarButton

on clickDisplayToolbarButton()
    set prefixes to {"1x", "2x", "3x", "4x", "Full"}
    tell application "System Events"
        tell process "Cinder64"
            set frontmost to true
            repeat with attempt from 1 to 80
                repeat with candidateWindow in windows
                    try
                        repeat with candidateToolbar in toolbars of candidateWindow
                            repeat with candidate in buttons of candidateToolbar
                                set candidateName to my elementText(candidate)
                                repeat with prefix in prefixes
                                    if candidateName starts with (prefix as text) then
                                        set candidatePosition to position of candidate
                                        set candidateSize to size of candidate
                                        click at {((item 1 of candidatePosition) + ((item 1 of candidateSize) / 2)), ((item 2 of candidatePosition) + ((item 2 of candidateSize) / 2))}
                                        return
                                    end if
                                end repeat
                            end repeat
                        end repeat
                    end try
                end repeat
                delay 0.25
            end repeat
        end tell
    end tell
    failSmoke("Timed out clicking display toolbar button")
end clickDisplayToolbarButton

on cinder64WindowCount()
    tell application "System Events"
        tell process "Cinder64"
            return count of windows
        end tell
    end tell
end cinder64WindowCount

on waitForWindowCount(expectedCount)
    repeat with attempt from 1 to 80
        if cinder64WindowCount() is expectedCount then return
        delay 0.25
    end repeat
    failSmoke("Timed out waiting for Cinder64 window count " & expectedCount)
end waitForWindowCount

on clickPromptCloseWithoutSaving()
    activateCinder64()
    tell application "System Events" to keystroke "d" using command down
end clickPromptCloseWithoutSaving

on anyVisibleElementContains(fragment)
    tell application "System Events"
        tell process "Cinder64"
            repeat with candidateWindow in windows
                try
                    repeat with candidate in entire contents of candidateWindow
                        set candidateName to my elementText(candidate)
                        if candidateName contains fragment then return true
                    end repeat
                end try
            end repeat
            try
                repeat with candidate in entire contents
                    set candidateName to my elementText(candidate)
                    if candidateName contains fragment then return true
                end repeat
            end try
        end tell
    end tell
    return false
end anyVisibleElementContains

on waitForVisibleElement(fragment)
    repeat with attempt from 1 to 80
        if anyVisibleElementContains(fragment) then return
        delay 0.25
    end repeat
    failSmoke("Timed out waiting for visible element containing " & fragment)
end waitForVisibleElement

on clickVisibleElement(fragment)
    tell application "System Events"
        tell process "Cinder64"
            repeat with attempt from 1 to 80
                repeat with candidateWindow in windows
                    try
                        repeat with candidate in entire contents of candidateWindow
                            set candidateName to my elementText(candidate)
                            if candidateName contains fragment then
                                click candidate
                                return
                            end if
                        end repeat
                    end try
                end repeat
                delay 0.25
            end repeat
        end tell
    end tell
    failSmoke("Timed out clicking visible element containing " & fragment)
end clickVisibleElement

on run argv
    set destructiveClose to ((item 1 of argv) as integer) is 1

    activateCinder64()

    widenMainWindow()
    waitForToolbarButton("Pause")
    waitForWindowCount(2)
    clickToolbarButton("Pause")
    waitForToolbarButton("Resume")
    clickToolbarButton("Resume")
    waitForToolbarButton("Pause")

    clickToolbarButton("State")
    waitForWindowCount(1)
    waitForVisibleElement("Slot 1")
    waitForVisibleElement("Save to Slot")
    waitForVisibleElement("Load Slot")
    clickToolbarButton("State")
    waitForWindowCount(2)
    delay 0.25

    clickDisplayToolbarButton()
    waitForWindowCount(1)
    waitForVisibleElement("Fullscreen")
    clickDisplayToolbarButton()
    waitForWindowCount(2)
    delay 0.25

    clickToolbarButton("Home")
    waitForWindowCount(1)
    tell application "System Events" to key code 53
    waitForWindowCount(2)
    delay 0.5

    if destructiveClose then
        clickToolbarButton("Home")
        waitForWindowCount(1)
        clickPromptCloseWithoutSaving()
    end if
end run
APPLESCRIPT

assert_log() {
  local needle="$1"
  if ! grep -Fq "$needle" "$RUNTIME_LOG_FILE"; then
    echo "Expected line in runtime log but did not find it: $needle" >&2
    echo "--- runtime.log tail ---" >&2
    tail -80 "$RUNTIME_LOG_FILE" >&2
    exit 1
  fi
}

assert_log "frontend toolbar intent pause"
assert_log "frontend toolbar intent resume"
assert_log "frontend toolbar intent returnHome"
assert_log "frontend toolbar intent cancelCloseGame"

if [[ "$DESTRUCTIVE_CLOSE" == "1" ]]; then
  for _ in $(seq 1 80); do
    if grep -Fq "close-game stop finished intent=returnHome" "$RUNTIME_LOG_FILE"; then
      break
    fi
    if ! cinder64_pid_is_alive "$LAUNCHED_PID"; then
      echo "Launched PID $LAUNCHED_PID exited during destructive close verification." >&2
      exit 1
    fi
    sleep 0.25
  done
  assert_log "close-game stop finished intent=returnHome"
fi

cinder64_capture_crash_snapshot "$AFTER_CRASHES" "$CRASH_REPORT_DIR"
NEW_CRASHES="$(cinder64_matching_new_crashes_for_pid "$BEFORE_CRASHES" "$AFTER_CRASHES" "$LAUNCHED_PID")"
if [[ -n "$NEW_CRASHES" ]]; then
  echo "A new Cinder64 crash report was created for PID $LAUNCHED_PID during toolbar verification:" >&2
  printf '%s\n' "$NEW_CRASHES" >&2
  exit 1
fi

echo "toolbar-controls:ok"
echo "bundle_path=$APP_BUNDLE"
echo "launched_pid=$LAUNCHED_PID"
echo "rom_path=$ROM_PATH"
echo "app_support_root=$APP_SUPPORT_ROOT"
echo "runtime_log=$RUNTIME_LOG_FILE"
