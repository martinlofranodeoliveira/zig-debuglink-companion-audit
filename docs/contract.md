# Input and Output Contract Specification

## 1. Command-Line Interface Contract

```
Usage:
  zig-debuglink-companion-audit [options]

Modes:
  --manifest <path>     Path to JSON manifest mapping ELF files to companion debug files.
  --elf <path>          Path to single main ELF binary. Requires --debug.
  --debug <path>        Path to companion debug file. Requires --elf.
  --assert              Run the self-contained asserting test suite against fixtures.
  --help, -h            Print command usage and exit with code 0.

Formatting Options:
  --json                Emit structured JSON report to standard output.
```

### Exit Codes
- `0`: All audited entries passed (`Verdict: Matched`), or `--assert` succeeded with 0 failures, or `--help` printed.
- `1`: At least one audited entry failed verification (`CrcMismatch`, `NameMismatch`, `MalformedDebuglink`, `MissingDebuglink`, `MissingDebugSections`, `IncompatibleElf`, `MissingCompanion`, `MissingMainElf`, `SymlinkRejected`, `NonRegularFile`, `FileModifiedDuringRead`).
- `2`: Command-line syntax error, manifest I/O or JSON parse error, or resource bound exceeded (`ResourceLimitExceeded`, `OpenFailed`).

---

## 2. Manifest JSON Schema Contract

The manifest must be a UTF-8 JSON document containing either:

### Object Form
```json
{
  "entries": [
    {
      "id": "app-binary",
      "elf": "fixtures/sample.bin",
      "companion": "fixtures/sample.debug"
    }
  ]
}
```

### Array Form
```json
[
  {
    "id": "app-binary",
    "elf": "fixtures/sample.bin",
    "companion": "fixtures/sample.debug"
  }
]
```

### Entry Field Constraints
- `id` *(string, optional)*: User-defined tag identifying the pair in output reports.
- `elf` *(string, required)*: Relative or absolute path to the main ELF file. Bounded to 4,096 bytes. Must not be a symlink or directory.
- `companion` *(string, required)*: Relative or absolute path to the companion `.debug` file. Bounded to 4,096 bytes. Must not be a symlink or directory.

---

## 3. JSON Output Schema Contract

When `--json` is supplied, the standard output is a JSON array of report objects:

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

### Report Object Properties
- `id`: Tag from manifest entry, or `null`.
- `verdict`: String enum name of the `Verdict`.
- `main_elf`: Path string as supplied in input.
- `companion`: Path string as supplied in input.
- `debuglink_name`: Basename embedded in `.gnu_debuglink`, or `null` if section missing/unreadable.
- `expected_crc`: Unsigned 32-bit integer parsed from debuglink, or `null`.
- `actual_crc`: Unsigned 32-bit integer computed over companion, or `null`.
- `elf_class`: Integer (`1` for ELF32, `2` for ELF64, `0` for unknown).
- `elf_machine`: Integer machine code from ELF header (e.g., `62` / `0x3e` for x86_64).
- `has_debug_sections`: Boolean indicating whether companion contains `.debug_*` or `.zdebug_*` sections.
- `main_build_id`: Hexadecimal string of GNU build-ID from main ELF, or `null`.
- `companion_build_id`: Hexadecimal string of GNU build-ID from companion, or `null`.
- `build_ids_agree`: Boolean (`true` if matching, `false` if differing, `null` if absent).
- `error_message`: Human-readable explanation string, or `null` on match.
