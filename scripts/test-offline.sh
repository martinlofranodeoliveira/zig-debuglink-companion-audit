#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

echo "=== 1. Building sample fixtures ==="
sh scripts/build_fixtures.sh

echo "=== 2. Running Zig Unit Tests ==="
zig test -lc -lelf src/tests.zig

echo "=== 3. Compiling ReleaseSafe Auditor CLI ==="
BIN_DIR="/tmp/zig-debuglink-bin"
mkdir -p "$BIN_DIR"
zig build-exe -lc -lelf src/main.zig -femit-bin="$BIN_DIR/audit" -O ReleaseSafe

echo "=== 4. Running Built-in Assertions ==="
"$BIN_DIR/audit" --assert

echo "=== 5. Running Built-in Assertions (JSON mode) ==="
"$BIN_DIR/audit" --assert --json

echo "=== 6. Auditing Sample Manifest ==="
"$BIN_DIR/audit" --manifest fixtures/manifest.json

echo "=== 7. Auditing Sample Manifest (JSON mode) ==="
"$BIN_DIR/audit" --manifest fixtures/manifest.json --json

echo "=== 8. Auditing Direct CLI Arguments ==="
"$BIN_DIR/audit" --elf fixtures/sample.bin --debug fixtures/sample.debug

echo "=== ALL TESTS COMPLETED SUCCESSFULLY ==="
