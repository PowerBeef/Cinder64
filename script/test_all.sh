#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
ARTIFACT_DIR="${CINDER64_TEST_ARTIFACT_ROOT:-$ROOT_DIR/test-artifacts/$TIMESTAMP}"
LOG_DIR="$ARTIFACT_DIR/logs"
SUMMARY_FILE="$ARTIFACT_DIR/summary.txt"

RUN_FULL=0
RUN_BOOT=0
RUN_VISUAL=0
ROM_PATH="${CINDER64_TEST_ROM:-}"

usage() {
  cat >&2 <<USAGE
usage: $0 [--full] [--boot] [--visual] [--rom PATH] [--artifacts PATH]
USAGE
}

while (($# > 0)); do
  case "$1" in
    --full)
      RUN_FULL=1
      ;;
    --boot)
      RUN_BOOT=1
      ;;
    --visual)
      RUN_VISUAL=1
      ;;
    --rom)
      if (($# < 2)); then
        usage
        exit 2
      fi
      ROM_PATH="$2"
      RUN_BOOT=1
      shift
      ;;
    --artifacts)
      if (($# < 2)); then
        usage
        exit 2
      fi
      ARTIFACT_DIR="$2"
      LOG_DIR="$ARTIFACT_DIR/logs"
      SUMMARY_FILE="$ARTIFACT_DIR/summary.txt"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

if [[ -n "$ROM_PATH" ]]; then
  RUN_BOOT=1
fi

case "$ARTIFACT_DIR" in
  /*) ;;
  *) ARTIFACT_DIR="$ROOT_DIR/$ARTIFACT_DIR" ;;
esac
LOG_DIR="$ARTIFACT_DIR/logs"
SUMMARY_FILE="$ARTIFACT_DIR/summary.txt"

if [[ -n "$ROM_PATH" ]]; then
  case "$ROM_PATH" in
    /*) ;;
    *) ROM_PATH="$ROOT_DIR/$ROM_PATH" ;;
  esac
fi

mkdir -p "$LOG_DIR" "$ARTIFACT_DIR/coverage"

{
  echo "artifact_dir=$ARTIFACT_DIR"
  echo "run_full=$RUN_FULL"
  echo "run_boot=$RUN_BOOT"
  echo "run_visual=$RUN_VISUAL"
  echo "rom_path=$ROM_PATH"
  echo
} >"$SUMMARY_FILE"

run_logged() {
  local name="$1"
  shift
  local log_file="$LOG_DIR/$name.log"

  {
    echo "==> $name"
    printf 'command:'
    printf ' %q' "$@"
    printf '\n'
  } | tee -a "$SUMMARY_FILE"

  set +e
  "$@" > >(tee "$log_file") 2>&1
  local status=$?
  set -e

  echo "$name status=$status" | tee -a "$SUMMARY_FILE"
  echo | tee -a "$SUMMARY_FILE" >/dev/null
  return "$status"
}

copy_if_present() {
  local source_path="$1"
  local target_path="$2"

  if [[ -f "$source_path" ]]; then
    mkdir -p "$(dirname "$target_path")"
    cp "$source_path" "$target_path"
    echo "copied_artifact=$target_path" >>"$SUMMARY_FILE"
  else
    echo "missing_artifact=$source_path" >>"$SUMMARY_FILE"
  fi
}

cd "$ROOT_DIR"

run_logged \
  "swift-tests" \
  swift test --enable-code-coverage --xunit-output "$ARTIFACT_DIR/swift-tests.xml"

coverage_path="$(swift test --show-codecov-path)"
echo "coverage_path=$coverage_path" >>"$SUMMARY_FILE"
copy_if_present "$coverage_path" "$ARTIFACT_DIR/coverage/Cinder64.json"

swift_testing_xml="$(find "$ARTIFACT_DIR" -maxdepth 1 -type f -name '*swift-testing.xml' -print -quit)"
if [[ -n "$swift_testing_xml" ]]; then
  echo "swift_testing_xml=$swift_testing_xml" >>"$SUMMARY_FILE"
else
  echo "swift_testing_xml=missing" >>"$SUMMARY_FILE"
fi

run_logged "app-bundle-helper-tests" ./script/test_app_bundle_helpers.sh

if (( RUN_FULL )); then
  run_logged \
    "swift-bridge-integration" \
    env CINDER64_RUN_BRIDGE_INTEGRATION=1 swift test --filter Cinder64Tests.Gopher64CoreHostIntegrationTests

  run_logged \
    "rust-bridge-tests" \
    cargo test --manifest-path ThirdParty/gopher64/cinder64_bridge/Cargo.toml

  run_logged \
    "bundle-assembly" \
    ./script/build_and_run.sh --prepare --print-bundle-path
fi

if (( RUN_BOOT )); then
  if [[ -z "$ROM_PATH" ]]; then
    echo "boot=skipped-no-rom" | tee -a "$SUMMARY_FILE"
  elif [[ ! -f "$ROM_PATH" ]]; then
    echo "boot=missing-rom:$ROM_PATH" | tee -a "$SUMMARY_FILE"
    exit 2
  else
    mkdir -p "$ARTIFACT_DIR/boot"
    run_logged \
      "boot-launch-services" \
      ./script/verify_launch_services_boot.sh "$ROM_PATH" "$ARTIFACT_DIR/boot/launch-services"
    run_logged \
      "boot-full" \
      ./script/verify_full_boot.sh "$ROM_PATH" "$ARTIFACT_DIR/boot/full"
  fi
fi

if (( RUN_VISUAL )); then
  if [[ -z "$ROM_PATH" ]]; then
    echo "visual=skipped-no-rom" | tee -a "$SUMMARY_FILE"
  elif [[ ! -f "$ROM_PATH" ]]; then
    echo "visual=missing-rom:$ROM_PATH" | tee -a "$SUMMARY_FILE"
    exit 2
  else
    mkdir -p "$ARTIFACT_DIR/visual"
    run_logged \
      "visual-boot" \
      ./script/verify_visual_boot.sh "$ROM_PATH" "$ARTIFACT_DIR/visual/run"
  fi
fi

echo "result=ok" | tee -a "$SUMMARY_FILE"
echo "artifacts=$ARTIFACT_DIR"
