#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="$ROOT_DIR/ThirdParty/gopher64/cinder64_bridge/Cargo.toml"

case "$PROFILE" in
  release)
    cargo build --manifest-path "$MANIFEST_PATH" --release
    TARGET_DIR="$ROOT_DIR/ThirdParty/gopher64/cinder64_bridge/target/release"
    ;;
  debug)
    cargo build --manifest-path "$MANIFEST_PATH"
    TARGET_DIR="$ROOT_DIR/ThirdParty/gopher64/cinder64_bridge/target/debug"
    ;;
  *)
    echo "usage: $0 [release|debug]" >&2
    exit 2
    ;;
esac

echo "$TARGET_DIR/libcinder64_gopher64.dylib"
