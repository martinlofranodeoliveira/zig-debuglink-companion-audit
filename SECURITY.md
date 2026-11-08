# Security Policy

Debuglink Companion Audit is a static analysis utility for auditing GNU `.gnu_debuglink` ELF references and companion debug symbol files. It does not execute audited binaries or follow untrusted symlinks.

## Reporting Security Issues

Report suspected security vulnerabilities privately through [GitHub Private Vulnerability Reporting](https://github.com/martinlofranodeoliveira/zig-debuglink-companion-audit/security/advisories/new).

Please include:
- A minimal reproducible synthetic test case or manifest.
- The exact version or commit of `zig-debuglink-companion-audit`.
- Observed behavior versus expected behavior.
- Operating system, architecture, and toolchain versions (`zig version`, `libelf`, `binutils`).

Do not include proprietary binaries, production secrets, or real credentials.

For general inquiries, visit [Lofrano Tecnologia](https://lofranotecnologia.com.br).

## Security Boundaries & Guarantees

1. **No Binary Execution**: Audited ELF files and debug companions are opened strictly read-only and parsed using `libelf` and pure Zig parsers. They are never executed, loaded as dynamic libraries, or interpreted.
2. **Symlink Rejection**: Manifest entries pointing to symbolic links are explicitly rejected before traversal using POSIX `lstat` checks.
3. **Detected-Change Protection**: Input files are inspected before and after reading with `fstat` to detect in-flight metadata modifications (size, mtime, inode, device).
4. **Strict Input Bounds**:
   - File paths: bounded to 4,096 bytes.
   - ELF sections inspected: bounded to 10,000 sections.
   - `.gnu_debuglink` payload size: bounded to 65,536 bytes.
   - Companion file size: bounded to 1 GiB.
5. **No Network Access**: The tool operates completely offline with `--network none` and requires zero external network calls or telemetry.
