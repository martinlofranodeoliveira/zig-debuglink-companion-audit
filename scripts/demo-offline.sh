#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

BIN_DIR="/tmp/zig-debuglink-bin"
mkdir -p "$BIN_DIR"

if [ ! -f "$BIN_DIR/audit" ]; then
  zig build-exe -lc -lelf src/main.zig -femit-bin="$BIN_DIR/audit" -O ReleaseSafe
fi

ASSERT_FLAG=0
for arg in "$@"; do
  if [ "$arg" = "--assert" ]; then
    ASSERT_FLAG=1
  fi
done

if [ "$ASSERT_FLAG" -eq 1 ]; then
  echo "=== Running Demonstration Assertions ==="
  "$BIN_DIR/audit" --assert
  "$BIN_DIR/audit" --assert --json
  "$BIN_DIR/audit" --manifest fixtures/manifest.json
  echo "=== Assertion Demo Succeeded ==="
  exit 0
fi

echo "=== Debuglink Companion Audit Demonstration ==="
echo "--- 1. Human-Readable Audit Output ---"
"$BIN_DIR/audit" --manifest fixtures/manifest.json

echo "--- 2. Structured JSON Output ---"
"$BIN_DIR/audit" --manifest fixtures/manifest.json --json
