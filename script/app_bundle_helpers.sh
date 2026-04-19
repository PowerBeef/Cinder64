#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

: "${APP_NAME:=Cinder64}"
: "${DIST_DIR:=$ROOT_DIR/dist}"

cinder64_runs_dir() {
  printf '%s/runs\n' "$DIST_DIR"
}

cinder64_new_run_id() {
  printf '%s-%s\n' "$(date '+%Y%m%dT%H%M%S')" "$$"
}

cinder64_bundle_path_for_run_id() {
  local run_id="$1"
  printf '%s/%s/%s.app\n' "$(cinder64_runs_dir)" "$run_id" "$APP_NAME"
}

cinder64_prepare_run_bundle_directory() {
  local run_id="$1"
  local bundle_path
  bundle_path="$(cinder64_bundle_path_for_run_id "$run_id")"

  mkdir -p "$(dirname "$bundle_path")"
  printf '%s\n' "$bundle_path"
}

cinder64_binary_path_for_bundle() {
  local bundle_path="$1"
  printf '%s/Contents/MacOS/%s\n' "$bundle_path" "$APP_NAME"
}

cinder64_update_latest_bundle_symlink() {
  local bundle_path="$1"
  local symlink_path="$DIST_DIR/$APP_NAME.app"
  local tmp_link="$DIST_DIR/.${APP_NAME}.app.link.$$"

  mkdir -p "$DIST_DIR"
  rm -f "$tmp_link"
  ln -s "$bundle_path" "$tmp_link"

  if [[ -e "$symlink_path" && ! -L "$symlink_path" ]]; then
    rm -rf "$symlink_path"
  fi

  mv -fh "$tmp_link" "$symlink_path"
}

cinder64_find_pids_for_bundle() {
  local bundle_path="$1"
  local binary_path
  binary_path="$(cinder64_binary_path_for_bundle "$bundle_path")"

  ps -axo pid=,command= | python3 -c '
import sys

target = sys.argv[1]

for line in sys.stdin:
    stripped = line.strip()
    if not stripped:
        continue
    pid, _, command = stripped.partition(" ")
    command = command.lstrip()
    if command == target or command.startswith(target + " "):
        print(pid)
' "$binary_path"
}

cinder64_wait_for_pid_for_bundle() {
  local bundle_path="$1"
  local attempts="${2:-120}"
  local pid=""

  for _ in $(seq 1 "$attempts"); do
    pid="$(cinder64_find_pids_for_bundle "$bundle_path" | head -n1)"
    if [[ -n "$pid" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
    sleep 0.25
  done

  return 1
}

cinder64_pid_is_alive() {
  local pid="$1"
  kill -0 "$pid" >/dev/null 2>&1
}

cinder64_wait_for_pid_exit() {
  local pid="$1"
  local attempts="${2:-40}"

  for _ in $(seq 1 "$attempts"); do
    if ! cinder64_pid_is_alive "$pid"; then
      return 0
    fi
    sleep 0.25
  done

  return 1
}

cinder64_stop_pid() {
  local pid="$1"

  if [[ -z "$pid" ]] || ! cinder64_pid_is_alive "$pid"; then
    return 0
  fi

  kill "$pid" >/dev/null 2>&1 || true
  if cinder64_wait_for_pid_exit "$pid"; then
    return 0
  fi

  kill -9 "$pid" >/dev/null 2>&1 || true
  cinder64_wait_for_pid_exit "$pid" 20
}

cinder64_window_info_for_pid() {
  local pid="$1"

  swift - "$pid" <<'SWIFT'
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1]) ?? -1
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let pidWindows = windows.filter {
    (($0[kCGWindowOwnerPID as String] as? Int) ?? -1) == pid &&
    (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0
}

print(pidWindows.count)
for window in pidWindows {
    let name = window[kCGWindowName as String] as? String ?? "untitled"
    print(name)
}
SWIFT
}

cinder64_capture_crash_snapshot() {
  local output_file="$1"
  local crash_report_dir="$2"

  if [[ -d "$crash_report_dir" ]]; then
    find "$crash_report_dir" -maxdepth 1 -type f -name 'Cinder64-*.ips' | sort >"$output_file"
  else
    : >"$output_file"
  fi
}

cinder64_matching_new_crashes_for_pid() {
  local before_file="$1"
  local after_file="$2"
  local target_pid="$3"

  comm -13 "$before_file" "$after_file" | python3 -c '
import pathlib
import re
import sys

target_pid = sys.argv[1]

for raw_path in sys.stdin:
    path = raw_path.strip()
    if not path:
        continue
    try:
        prefix = pathlib.Path(path).read_text(errors="ignore")[:8192]
    except OSError:
        continue
    match = re.search(r"\"pid\"\s*:\s*(\d+)", prefix)
    if match and match.group(1) == target_pid:
        print(path)
' "$target_pid"
}

cinder64_prune_run_bundles() {
  local keep_count="${1:-5}"
  shift || true
  local latest_symlink="$DIST_DIR/$APP_NAME.app"
  local latest_target=""
  local runs_root
  local -a run_dirs=()
  local -a protected_bundles=("$@")
  local run_dir
  local index=0

  runs_root="$(cinder64_runs_dir)"
  [[ -d "$runs_root" ]] || return 0

  if [[ -L "$latest_symlink" ]]; then
    latest_target="$(readlink "$latest_symlink")"
  fi

  while IFS= read -r run_dir; do
    run_dirs+=("$run_dir")
  done < <(find "$runs_root" -mindepth 1 -maxdepth 1 -type d | sort -r)

  for run_dir in "${run_dirs[@]}"; do
    local bundle_path="$run_dir/$APP_NAME.app"

    index=$((index + 1))
    if (( index <= keep_count )); then
      continue
    fi

    if [[ "$bundle_path" == "$latest_target" ]]; then
      continue
    fi

    if [[ " ${protected_bundles[*]} " == *" $bundle_path "* ]]; then
      continue
    fi

    if [[ -n "$(cinder64_find_pids_for_bundle "$bundle_path")" ]]; then
      continue
    fi

    rm -rf "$run_dir"
  done
}
