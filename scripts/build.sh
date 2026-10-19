#!/bin/bash
# Build MQ80 Studio without Xcode (Command Line Tools only).
# Usage: scripts/build.sh [release|debug]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-release}"
BUILD="$ROOT/.build-manual"
mkdir -p "$BUILD/tmp" "$BUILD/modulecache"
export TMPDIR="$BUILD/tmp"
export CLANG_MODULE_CACHE_PATH="$BUILD/modulecache"

CORE=("$ROOT"/Sources/MQ80Core/*.swift)
if [ "$MODE" = "debug" ]; then
  FLAGS=(-Onone -g -parse-as-library -module-cache-path "$BUILD/modulecache")
else
  FLAGS=(-O -parse-as-library -module-cache-path "$BUILD/modulecache")
fi

echo "== building iqunixctl =="
swiftc "${FLAGS[@]}" -o "$BUILD/iqunixctl" "${CORE[@]}" "$ROOT/Sources/mq80ctl/CLI.swift"

echo "== building IQUNIX-DRIVE =="
swiftc "${FLAGS[@]}" -o "$BUILD/IQUNIX-DRIVE" "${CORE[@]}" "$ROOT"/Sources/MQ80Studio/*.swift

# Bundle VIA keyboard definitions next to the executables so the CLI (and the
# app when run from dist) can resolve definitions without SwiftPM resources.
if [ -d "$ROOT/Resources/VIAKeyboardDefinitions" ]; then
  rm -rf "$BUILD/VIAKeyboardDefinitions"
  cp -R "$ROOT/Resources/VIAKeyboardDefinitions" "$BUILD/VIAKeyboardDefinitions"
fi

echo "OK: $BUILD/iqunixctl  $BUILD/IQUNIX-DRIVE"
