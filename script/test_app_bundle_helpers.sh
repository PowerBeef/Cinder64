#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cinder64-bundle-helper-test.XXXXXX")"
DIST_DIR="$TEST_ROOT/dist"
APP_NAME="Cinder64"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

source "$ROOT_DIR/script/app_bundle_helpers.sh"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [[ "$actual" != "$expected" ]]; then
    echo "assert_eq failed: $message" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

run_id="20260419T101500-4242"
bundle_path="$(cinder64_bundle_path_for_run_id "$run_id")"
expected_bundle_path="$DIST_DIR/runs/$run_id/$APP_NAME.app"
assert_eq "$bundle_path" "$expected_bundle_path" "bundle path uses dist/runs/<run-id>/Cinder64.app"

prepared_bundle_path="$(cinder64_prepare_run_bundle_directory "$run_id")"
assert_eq "$prepared_bundle_path" "$expected_bundle_path" "prepare returns the created bundle path"
if [[ ! -d "$(dirname "$bundle_path")" ]]; then
  echo "prepare should create the run directory" >&2
  exit 1
fi

mkdir -p "$bundle_path/Contents/MacOS"
printf 'binary' >"$bundle_path/Contents/MacOS/$APP_NAME"

cinder64_update_latest_bundle_symlink "$bundle_path"
latest_link="$DIST_DIR/$APP_NAME.app"
if [[ ! -L "$latest_link" ]]; then
  echo "latest bundle path should be a symlink" >&2
  exit 1
fi
assert_eq "$(readlink "$latest_link")" "$bundle_path" "latest bundle symlink points at the prepared bundle"

older_run="20260419T091000-1111"
middle_run="20260419T100000-2222"
newest_run="20260419T110000-3333"

for id in "$older_run" "$middle_run" "$newest_run"; do
  mkdir -p "$DIST_DIR/runs/$id/$APP_NAME.app"
done

cinder64_update_latest_bundle_symlink "$DIST_DIR/runs/$middle_run/$APP_NAME.app"
cinder64_prune_run_bundles 2

if [[ -e "$DIST_DIR/runs/$older_run" ]]; then
  echo "oldest inactive run should be pruned" >&2
  exit 1
fi

if [[ ! -e "$DIST_DIR/runs/$middle_run/$APP_NAME.app" ]]; then
  echo "symlink target should be preserved during pruning" >&2
  exit 1
fi

if [[ ! -e "$DIST_DIR/runs/$newest_run/$APP_NAME.app" ]]; then
  echo "newest run should be preserved during pruning" >&2
  exit 1
fi

echo "app-bundle-helpers:ok"
