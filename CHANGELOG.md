# Changelog

All notable changes to `zig-debuglink-companion-audit` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-08

### Added
- Core IEEE 802.3 pure Zig CRC32 calculation and incremental updater matching GNU `calc_gnu_debuglink_crc32`.
- GNU `.gnu_debuglink` payload parser with strict NUL-termination, zero-padding alignment, and endianness handling.
- ELF metadata and section inspector using `libelf` and `gelf` C ABI interop.
- Companion file auditor comparing architecture, machine, byte-order, debug sections (`.debug_*`), and GNU build IDs.
- Symlink rejection and detected-change read barrier verification using POSIX `lstat` and `fstat`.
- CLI interface supporting `--manifest <path>`, `--elf <path>`, `--debug <path>`, `--json`, and `--assert` modes.
- Complete offline test fixtures built with GCC and GNU `objcopy` (`--only-keep-debug`, `--strip-debug`, `--add-gnu-debuglink`).
- Comprehensive unit test suite and self-contained 9-scenario assertion runner.
- English and Brazilian Portuguese documentation (`README.md`, `README.pt-BR.md`, `docs/contract.md`, `docs/design.md`, `PRODUCT.md`).
