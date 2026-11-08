# Debuglink Companion Audit — Product Specification

## 1. Executive Summary

**Debuglink Companion Audit** (`zig-debuglink-companion-audit`) is an independent, deterministic ELF auxiliary debug information auditor written in pure Zig. It inspects and verifies GNU `.gnu_debuglink` sections using maintained `libelf` and `gelf` C ABI interfaces alongside a native IEEE 802.3 CRC-32 engine. It guarantees that an audited binary strictly references the supplied companion file and carries its exact, uncorrupted CRC-32 checksum.

Designed for reproducible software packaging, debug symbol servers, continuous delivery pipelines, and post-build artifact verification, this tool enforces strict boundaries: it operates exclusively on an explicit manifest of owned files, never touches host debug stores, rejects symlinks, verifies file stability across read barriers, and never executes audited binaries.

---

## 2. Core Capabilities

- **Strict Manifest Resolution**: Accepts only explicitly mapped ELF and companion paths via JSON manifest or direct CLI flags (`--manifest`, `--elf`, `--debug`).
- **Standard GNU BFD Debuglink Specification Compliance**:
  - Validates a single `.gnu_debuglink` section per binary.
  - Rejects duplicate `.gnu_debuglink` sections.
  - Enforces pure basename format without directories, drive letters, or path separators (`/`, `\`, `:`).
  - Enforces mandatory NUL (`\0`) termination.
  - Enforces exact four-byte alignment with zeroed padding bytes (`\x00`).
  - Decodes target-endian CRC32 (little-endian and big-endian) according to ELF header byte order (`EI_DATA`).
  - Rejects trailing payload bytes after the 4-byte CRC.
- **Companion File Integrity Verification**:
  - Computes the IEEE 802.3 polynomial (`0xEDB88320`) CRC-32 across every byte of the companion file.
  - Compares the computed checksum against the embedded debuglink CRC field.
- **ELF Architecture & Compatibility Check**:
  - Validates ELF magic (`\x7fELF`), class (`ELFCLASS32` or `ELFCLASS64`), data encoding (`ELFDATA2LSB` or `ELFDATA2MSB`), and machine type (`e_machine`).
  - Verifies that the companion ELF matches the main executable in architecture and endianness.
  - Detects presence of debug sections (`.debug_*` or `.zdebug_*`).
  - Inspects GNU build IDs (`.note.gnu.build-id`) and reports agreement without treating build-ID presence as an authenticity proof.
- **Security & Integrity Protections**:
  - Symlink rejection via POSIX `lstat` prior to opening.
  - Non-regular file rejection (blocks FIFOs, sockets, character/block devices, directories).
  - Detected-change barrier: compares pre-open `lstat`, post-open `fstat`, and post-read `fstat` (inode, device, file size, modification time) to flag concurrent tampering.
  - Strict numeric resource bounds (file size ≤ 1 GiB, path length ≤ 4096 bytes, sections ≤ 10,000, payload ≤ 65,536 bytes).

---

## 3. Verdict State Machine & Error Taxonomy

Every audit evaluation terminates deterministically in one of the following structured verdicts:

| Verdict | Exit Code | Description |
| :--- | :---: | :--- |
| `Matched` | `0` | All structural, name, architecture, debug section, and CRC checks passed. |
| `CrcMismatch` | `1` | Companion file contents do not match the expected `.gnu_debuglink` CRC-32. |
| `NameMismatch` | `1` | Companion file basename does not match the filename in `.gnu_debuglink`. |
| `MalformedDebuglink` | `1` | Debuglink payload violates GNU BFD formatting (missing NUL, bad padding, truncated CRC, trailing bytes, duplicate section). |
| `MissingDebuglink` | `1` | Main ELF does not contain a `.gnu_debuglink` section. |
| `MissingDebugSections`| `1` | Companion file does not contain expected `.debug_*` or `.zdebug_*` sections. |
| `IncompatibleElf` | `1` | ELF magic invalid, or main/companion architecture, class, or endianness mismatch. |
| `MissingCompanion` | `1` | Specified companion debug file does not exist or is inaccessible. |
| `MissingMainElf` | `1` | Specified main ELF binary does not exist or is inaccessible. |
| `SymlinkRejected` | `1` | Input path resolves to a symbolic link, which is strictly prohibited. |
| `NonRegularFile` | `1` | Input is a directory, pipe, device, or socket rather than a regular file. |
| `FileModifiedDuringRead` | `1` | File metadata changed between opening and completion barriers. |
| `ResourceLimitExceeded` | `2` | Input exceeded safety caps (path length > 4096, size > 1 GiB, sections > 10,000). |
| `OpenFailed` | `2` | System call or permission error encountered while opening files. |

---

## 4. Verification & Testing Strategy

- **Real Toolchain Fixtures**: Constructed with GCC and GNU `objcopy` using `--only-keep-debug`, `--strip-debug`, and `--add-gnu-debuglink`.
- **Golden Byte-Level Test Vectors**: Little-endian and big-endian test vectors verify pure CRC decoding independent of native host architecture.
- **Zero-Network Isolation**: All validations execute within Docker containers configured with `--network none`, `--cap-drop ALL`, and `no-new-privileges`.
- **Deterministic Assertion Suite**: Packaged CLI includes `--assert` mode exercising 9 critical behavioral scenarios, guaranteeing reproducibility across platforms.

---

## 5. Metadata & Provenance

- **Maintainer**: Lofrano Tecnologia ([https://lofranotecnologia.com.br](https://lofranotecnologia.com.br))
- **Author**: Martin Lofrano de Oliveira
- **License**: MIT License © 2026 Lofrano Tecnologia
- **Language**: Zig (0.14+ / 0.17+)
- **System Dependencies**: `libc`, `libelf` (elfutils)
