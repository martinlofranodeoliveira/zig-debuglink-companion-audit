#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"
mkdir -p fixtures/src

if [ ! -f fixtures/src/sample.c ]; then
  cat << 'EOF' > fixtures/src/sample.c
#include <stdio.h>

int main(void) {
    printf("hello debuglink audit\n");
    return 0;
}
EOF
fi

gcc -g -O0 -o fixtures/sample.full fixtures/src/sample.c
objcopy --only-keep-debug fixtures/sample.full fixtures/sample.debug
objcopy --strip-debug fixtures/sample.full fixtures/sample.bin
objcopy --add-gnu-debuglink=fixtures/sample.debug fixtures/sample.bin

echo "Fixtures built successfully."
