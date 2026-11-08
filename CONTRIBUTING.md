# Contributing to Debuglink Companion Audit

Thank you for your interest in contributing! This project is maintained by [Lofrano Tecnologia](https://lofranotecnologia.com.br) under the MIT License.

## Development Workflow & Guidelines

1. **Deterministic Offline Execution**:
   All test suites, assertions, and demonstration scripts must run fully offline without network access (`--network none`). Zero runtime dependencies are permitted beyond Zig, `libc`, and `libelf`.

2. **Code Style & Organization**:
   - Write idiomatic Zig code compatible with Zig 0.14+.
   - Keep C ABI bindings cleanly isolated in `src/libelf_types.zig`.
   - Ensure all allocations have matching deallocations without memory leaks.
   - Retain complete input boundary checks (path lengths, section counts, file sizes).

3. **Running Quality Checks**:
   Before submitting changes, ensure the full suite passes:
   ```sh
   sh scripts/build_fixtures.sh
   sh scripts/test-offline.sh
   sh scripts/demo-offline.sh --assert
   ```

4. **Pull Requests**:
   - Ensure clear commit messages.
   - Include regression tests for any bug fixes.
   - Avoid checking in large compiled binaries into git (`main`, `*.o`, `sample.bin` should only be built by scripts).
