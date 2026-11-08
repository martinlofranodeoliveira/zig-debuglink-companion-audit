# Debuglink Companion Audit

[![CI](https://github.com/martinlofranodeoliveira/zig-debuglink-companion-audit/actions/workflows/ci.yml/badge.svg)](https://github.com/martinlofranodeoliveira/zig-debuglink-companion-audit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.14%2B%20%7C%200.17-orange.svg)](https://ziglang.org)

An independent, deterministic ELF auxiliary debug information auditor written in pure Zig. It inspects GNU `.gnu_debuglink` sections using maintained `libelf` and `gelf` C ABI interfaces and verifies companion debug files against GNU `objcopy`/`readelf` reference behaviors.

[**Documentação em Português (Brasil)**](README.pt-BR.md)

---

## Features

- **Strict Explicit Manifests**: Audits only explicitly configured ELF files and permitted debug companions. Never searches host directories or queries system symbol stores.
- **GNU BFD Debuglink Specification Compliance**:
  - Validates single `.gnu_debuglink` section per binary; rejects duplicate sections.
  - Enforces exact NUL (`\0`) termination and zeroed four-byte padding.
  - Resolves target-endian CRC32 fields according to ELF header byte order (`EI_DATA`).
  - Rejects trailing bytes after the CRC field.
- **Full File CRC-32 Verification**: Computes the IEEE 802.3 CRC-32 (`0xEDB88320`) across every byte of the companion debug file using an $O(1)$ streaming window.
- **Architecture & Compatibility Checks**: Ensures that companion debug files match the parent ELF binary in class (`ELFCLASS32`/`ELFCLASS64`), byte order, and machine architecture (`e_machine`).
- **Build ID & Debug Section Inspection**: Checks for `.debug_*` sections and compares GNU build IDs (`.note.gnu.build-id`) when available.
- **Tampering & Symlink Defenses**:
  - Rejects symbolic links before traversal using POSIX `lstat`.
  - Enforces before/after file descriptor metadata consistency checks (`fstat`) to detect in-flight file modifications.
  - Strictly bounded resource caps (file size ≤ 1 GiB, path length ≤ 4096 bytes, sections ≤ 10,000).

---

## Installation & Requirements

### Requirements
- **Zig**: 0.14+ or 0.17+
- **libelf**: `libelf-dev` (from `elfutils`)
- **C Library**: GNU `libc` or musl
- **binutils** *(optional, for rebuilding test fixtures)*: `gcc`, `objcopy`, `readelf`

### Building from Source

```sh
# Clone repository
git clone https://github.com/martinlofranodeoliveira/zig-debuglink-companion-audit.git
cd zig-debuglink-companion-audit

# Build release binary
zig build-exe -lc -lelf src/main.zig -femit-bin=audit -O ReleaseSafe
```

---

## Usage

### 1. Direct File Audit

```sh
./audit --elf fixtures/sample.bin --debug fixtures/sample.debug
```

Example Output:
```
Verdict: Matched
  Main ELF:          fixtures/sample.bin
  Companion:         fixtures/sample.debug
  Debuglink Name:    sample.debug
  Expected CRC32:    0x8a5d42ff
  Computed CRC32:    0x8a5d42ff
  ELF Class:         ELF64
  ELF Machine:       0x003e
  Debug Sections:    true
  Main Build-ID:     57b5856da998b70b4ba071220f44655f0070b8da
  Companion Build-ID:57b5856da998b70b4ba071220f44655f0070b8da
  Build-IDs Match:   true
```

### 2. Manifest Audit

```sh
./audit --manifest fixtures/manifest.json
```

Manifest JSON format (`fixtures/manifest.json`):
```json
{
  "entries": [
    {
      "id": "sample-companion-match",
      "elf": "fixtures/sample.bin",
      "companion": "fixtures/sample.debug"
    }
  ]
}
```

### 3. Structured JSON Output

```sh
./audit --manifest fixtures/manifest.json --json
```

Output:
```json
[
  {
    "id": "sample-companion-match",
    "verdict": "Matched",
    "main_elf": "fixtures/sample.bin",
    "companion": "fixtures/sample.debug",
    "debuglink_name": "sample.debug",
    "expected_crc": 2321367807,
    "actual_crc": 2321367807,
    "elf_class": 2,
    "elf_machine": 62,
    "has_debug_sections": true,
    "main_build_id": "57b5856da998b70b4ba071220f44655f0070b8da",
    "companion_build_id": "57b5856da998b70b4ba071220f44655f0070b8da",
    "build_ids_agree": true,
    "error_message": null
  }
]
```

### 4. Running Built-in Self-Contained Assertions

```sh
./audit --assert
```

Runs 9 critical behavioral assertions:
1. Freshly split ELF and companion match with exact CRC.
2. Single-byte corruption in companion produces `CrcMismatch`.
3. Incorrect companion basename produces `NameMismatch`.
4. Companion lacking `.debug_*` sections produces `MissingDebugSections`.
5. Binary without `.gnu_debuglink` produces `MissingDebuglink`.
6. Non-existent companion produces `MissingCompanion`.
7. Symbolic link companion is rejected (`SymlinkRejected`).
8. Little-endian and big-endian target-endian CRC decoding test vectors pass.
9. Structural errors in debuglink payloads (truncated, non-zero padding, missing NUL) are rejected.

---

## Offline Testing

The project includes offline test runners that run without internet access:

```sh
# Run offline test suite
sh scripts/test-offline.sh

# Run offline assertion demonstration
sh scripts/demo-offline.sh --assert
```

---

## Documentation

- [Input and Output Contract Specification](docs/contract.md)
- [Architecture and Technical Design](docs/design.md)
- [Product Specification](PRODUCT.md)
- [Changelog](CHANGELOG.md)
- [Security Policy](SECURITY.md)

---

## License

MIT License © 2026 [Lofrano Tecnologia](https://lofranotecnologia.com.br).
Developed by Martin Lofrano de Oliveira.
