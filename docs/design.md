# Architecture and Technical Design

## 1. Architectural Overview

```
                      +-----------------------------+
                      |           CLI               |
                      |       (src/main.zig)        |
                      +--------------+--------------+
                                     |
              +----------------------+----------------------+
              |                                             |
              v                                             v
  +-----------------------+                     +-----------------------+
  |    Manifest Parser    |                     |    Assertion Suite    |
  | (std.json streaming)  |                     | (9 golden scenarios)  |
  +-----------+-----------+                     +-----------+-----------+
              |                                             |
              +----------------------+----------------------+
                                     |
                                     v
                      +-----------------------------+
                      |      Companion Auditor      |
                      |      (src/auditor.zig)      |
                      +--------------+--------------+
                                     |
         +---------------------------+---------------------------+
         |                           |                           |
         v                           v                           v
+-----------------+         +-----------------+         +-----------------+
|  POSIX & libelf |         |  GNU Debuglink  |         |   Pure Zig CRC  |
|     Bindings    |         |  Payload Parser |         |     Engine      |
| (libelf_types)  |         | (debuglink.zig) |         |   (src/crc.zig) |
+-----------------+         +-----------------+         +-----------------+
```

---

## 2. GNU `.gnu_debuglink` Section Layout

According to the GNU BFD / GDB specification, the `.gnu_debuglink` section layout is structured as follows:

```
+-------------------------------------------------------+
|  Basename of companion file (ASCII / UTF-8)           |
+-------------------------------------------------------+
|  NUL byte (0x00) terminator                           |
+-------------------------------------------------------+
|  0 to 3 padding bytes (0x00) for 4-byte alignment     |
+-------------------------------------------------------+
|  4-byte CRC32 (CRC of companion file in target endian)|
+-------------------------------------------------------+
```

### Alignment Calculation
Let $L$ be the string length of the filename.
The null-terminated string has length $S = L + 1$.
The remainder modulo 4 is $R = S \pmod 4$.
The padding length $P$ is:
$$P = \begin{cases} 0 & \text{if } R = 0 \\ 4 - R & \text{if } R \neq 0 \end{cases}$$
The total section size must be exactly:
$$\text{Total Size} = S + P + 4$$
Any deviation (missing NUL terminator, non-zero padding byte, truncated CRC, or trailing bytes beyond $S + P + 4$) is classified as `MalformedDebuglink`.

---

## 3. Pure Zig CRC-32 Engine

The GNU debuglink checksum algorithm corresponds to standard IEEE 802.3 CRC-32 (polynomial `0xEDB88320` reversed / bit-reflected):
- Initial CRC register value: `0xFFFFFFFF`
- Reflected input bytes
- Precomputed 256-entry lookup table initialized at compile time via `@setEvalBranchQuota(5000)`
- Final XOR value: `0xFFFFFFFF`

To process large companion files (up to 1 GiB) within a bounded 1 GiB process memory budget, `auditor.zig` streams file chunks through a 64 KiB buffer using `crc.updateCrc`, maintaining $O(1)$ heap memory overhead.

---

## 4. libelf C ABI Interoperability

Rather than relying on macro-heavy or volatile compiler translation tools, `zig-debuglink-companion-audit` declares explicit `extern "c"` C ABI types and function prototypes matching `libelf` and `gelf` from elfutils:
- `elf_version(EV_CURRENT)`
- `elf_begin(fd, ELF_C_READ, null)`
- `elf_end(elf)`
- `elf_nextscn(elf, scn)`
- `elf_strptr(elf, shstrndx, offset)`
- `elf_getdata(scn, null)`
- `gelf_getehdr(elf, ehdr)`
- `gelf_getshdr(scn, shdr)`

This guarantees stable cross-compilation across Zig toolchain revisions without requiring unstable `@cImport`.

---

## 5. Security & Threat Model

### Threat: Malicious or Misleading Symbolic Links
- **Risk**: An attacker provides a manifest entry pointing to `/etc/passwd` or an arbitrary host symlink.
- **Mitigation**: `auditor.zig` calls POSIX `lstat` prior to opening. If `(st_mode & S_IFMT) == S_IFLNK`, execution immediately aborts with `SymlinkRejected`.

### Threat: In-Flight Time-of-Check to Time-of-Use (TOCTOU) Modification
- **Risk**: A background process swaps or appends bytes to the companion file while the auditor is calculating its CRC.
- **Mitigation**: The auditor captures `st_dev`, `st_ino`, `st_size`, and `st_mtime` using `lstat` before opening, checks `fstat` immediately after opening, and checks `fstat` again after reading all bytes. Any discrepancy triggers `FileModifiedDuringRead`.

### Threat: Resource Exhaustion / Memory Bomb
- **Risk**: A malformed ELF file containing millions of sections or gigantic debuglink section sizes attempts to exhaust process memory.
- **Mitigation**: Strict numeric limits are enforced before allocation:
  - Max path length: 4,096 bytes
  - Max ELF sections traversed: 10,000
  - Max `.gnu_debuglink` payload size: 65,536 bytes
  - Max companion file size: 1 GiB
