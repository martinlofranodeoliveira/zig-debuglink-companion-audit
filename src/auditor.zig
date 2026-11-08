const std = @import("std");
const libelf = @import("libelf_types.zig");
const crc = @import("crc.zig");
const debuglink = @import("debuglink.zig");

pub const Verdict = enum {
    Matched,
    CrcMismatch,
    NameMismatch,
    MalformedDebuglink,
    MissingDebuglink,
    MissingDebugSections,
    IncompatibleElf,
    MissingCompanion,
    MissingMainElf,
    SymlinkRejected,
    NonRegularFile,
    FileModifiedDuringRead,
    ResourceLimitExceeded,
    OpenFailed,
};

pub const Limits = struct {
    pub const max_path_len: usize = 4096;
    pub const max_sections: usize = 10000;
    pub const max_debuglink_size: usize = 65536;
    pub const max_file_size: i64 = 1024 * 1024 * 1024; // 1 GiB
};

pub const AuditReport = struct {
    verdict: Verdict,
    main_elf: []const u8,
    companion: []const u8,
    debuglink_name: ?[]const u8,
    expected_crc: ?u32,
    actual_crc: ?u32,
    elf_class: u8,
    elf_machine: u16,
    has_debug_sections: bool,
    main_build_id: ?[]const u8,
    companion_build_id: ?[]const u8,
    build_ids_agree: ?bool,
    error_message: ?[]const u8,

    pub fn deinit(self: AuditReport, allocator: std.mem.Allocator) void {
        if (self.debuglink_name) |dn| allocator.free(dn);
        if (self.main_build_id) |bid| allocator.free(bid);
        if (self.companion_build_id) |bid| allocator.free(bid);
    }
};

fn getBasename(path: []const u8) []const u8 {
    var last_sep: ?usize = null;
    for (path, 0..) |c, i| {
        if (c == '/' or c == '\\') {
            last_sep = i;
        }
    }
    if (last_sep) |idx| {
        return path[idx + 1 ..];
    }
    return path;
}

pub fn toZ(buf: []u8, slice: []const u8) ![:0]const u8 {
    if (slice.len >= buf.len) return error.PathTooLong;
    @memcpy(buf[0..slice.len], slice);
    buf[slice.len] = 0;
    return buf[0..slice.len :0];
}

fn extractBuildId(allocator: std.mem.Allocator, elf: *libelf.Elf, shstrndx: usize) ?[]const u8 {
    var scn: ?*libelf.Elf_Scn = null;
    var count: usize = 0;
    while (count < Limits.max_sections) : (count += 1) {
        scn = libelf.elf_nextscn(elf, scn);
        if (scn == null) break;
        var shdr: libelf.GElf_Shdr = undefined;
        if (libelf.gelf_getshdr(scn, &shdr) != null) {
            if (shdr.sh_type == libelf.SHT_NOTE) {
                if (libelf.elf_strptr(elf, shstrndx, shdr.sh_name)) |sec_name| {
                    const name_slice = std.mem.span(sec_name);
                    if (std.mem.eql(u8, name_slice, ".note.gnu.build-id")) {
                        if (libelf.elf_getdata(scn, null)) |data| {
                            if (data.d_buf != null and data.d_size >= 16) {
                                const raw_ptr: [*]const u8 = @ptrCast(data.d_buf);
                                const buf = raw_ptr[0..data.d_size];
                                // Note structure: namesz (4), descsz (4), type (4), name (padded), desc
                                const namesz = std.mem.readInt(u32, buf[0..4], .little);
                                const descsz = std.mem.readInt(u32, buf[4..8], .little);
                                const n_type = std.mem.readInt(u32, buf[8..12], .little);
                                if (n_type == libelf.NT_GNU_BUILD_ID and descsz > 0 and descsz <= 64) {
                                    const name_pad = (namesz + 3) & ~@as(u32, 3);
                                    const desc_offset = 12 + name_pad;
                                    if (desc_offset + descsz <= buf.len) {
                                        const desc_bytes = buf[desc_offset .. desc_offset + descsz];
                                        var hex_buf: [128]u8 = undefined;
                                        const hex_chars = "0123456789abcdef";
                                        for (desc_bytes, 0..) |b, i| {
                                            hex_buf[i * 2] = hex_chars[b >> 4];
                                            hex_buf[i * 2 + 1] = hex_chars[b & 0x0f];
                                        }
                                        return allocator.dupe(u8, hex_buf[0 .. desc_bytes.len * 2]) catch null;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return null;
}

pub fn auditFiles(
    allocator: std.mem.Allocator,
    main_elf_path: []const u8,
    companion_path: []const u8
) AuditReport {
    _ = libelf.elf_version(libelf.EV_CURRENT);

    var empty_report = AuditReport{
        .verdict = .OpenFailed,
        .main_elf = main_elf_path,
        .companion = companion_path,
        .debuglink_name = null,
        .expected_crc = null,
        .actual_crc = null,
        .elf_class = 0,
        .elf_machine = 0,
        .has_debug_sections = false,
        .main_build_id = null,
        .companion_build_id = null,
        .build_ids_agree = null,
        .error_message = null,
    };

    if (main_elf_path.len == 0 or main_elf_path.len > Limits.max_path_len or
        companion_path.len == 0 or companion_path.len > Limits.max_path_len)
    {
        empty_report.verdict = .ResourceLimitExceeded;
        empty_report.error_message = "File path exceeds maximum allowed length";
        return empty_report;
    }

    // 1. Inspect main ELF via lstat (check symlink / non-regular)
    var main_z_buf: [Limits.max_path_len + 1]u8 = undefined;
    const main_z = toZ(&main_z_buf, main_elf_path) catch {
        empty_report.verdict = .ResourceLimitExceeded;
        empty_report.error_message = "Cannot format main ELF path";
        return empty_report;
    };

    var main_st_pre: libelf.Stat = undefined;
    if (libelf.lstat(main_z.ptr, &main_st_pre) != 0) {
        empty_report.verdict = .MissingMainElf;
        empty_report.error_message = "Main ELF file not found or inaccessible";
        return empty_report;
    }

    if ((main_st_pre.st_mode & libelf.S_IFMT) == libelf.S_IFLNK) {
        empty_report.verdict = .SymlinkRejected;
        empty_report.error_message = "Main ELF is a symbolic link; symlinks are rejected";
        return empty_report;
    }

    if ((main_st_pre.st_mode & libelf.S_IFMT) != libelf.S_IFREG) {
        empty_report.verdict = .NonRegularFile;
        empty_report.error_message = "Main ELF is not a regular file";
        return empty_report;
    }

    if (main_st_pre.st_size > Limits.max_file_size) {
        empty_report.verdict = .ResourceLimitExceeded;
        empty_report.error_message = "Main ELF file exceeds 1 GiB size limit";
        return empty_report;
    }

    const main_fd = libelf.open(main_z.ptr, libelf.O_RDONLY);
    if (main_fd < 0) {
        empty_report.verdict = .MissingMainElf;
        empty_report.error_message = "Cannot open main ELF file";
        return empty_report;
    }
    defer _ = libelf.close(main_fd);

    var main_st_post: libelf.Stat = undefined;
    if (libelf.fstat(main_fd, &main_st_post) != 0 or
        main_st_post.st_size != main_st_pre.st_size or
        main_st_post.st_ino != main_st_pre.st_ino or
        main_st_post.st_dev != main_st_pre.st_dev)
    {
        empty_report.verdict = .FileModifiedDuringRead;
        empty_report.error_message = "Main ELF file modified during opening barrier";
        return empty_report;
    }

    const main_elf = libelf.elf_begin(main_fd, libelf.ELF_C_READ, null);
    if (main_elf == null) {
        empty_report.verdict = .IncompatibleElf;
        empty_report.error_message = "libelf failed to parse main ELF";
        return empty_report;
    }
    defer _ = libelf.elf_end(main_elf);

    var main_ehdr: libelf.GElf_Ehdr = undefined;
    if (libelf.gelf_getehdr(main_elf, &main_ehdr) == null) {
        empty_report.verdict = .IncompatibleElf;
        empty_report.error_message = "Cannot read main ELF header";
        return empty_report;
    }

    empty_report.elf_class = main_ehdr.e_ident[libelf.EI_CLASS];
    empty_report.elf_machine = main_ehdr.e_machine;

    const is_little = main_ehdr.e_ident[libelf.EI_DATA] == libelf.ELFDATA2LSB;

    // Scan main ELF sections for .gnu_debuglink
    var scn: ?*libelf.Elf_Scn = null;
    var debuglink_count: usize = 0;
    var debuglink_payload_bytes: ?[]const u8 = null;
    var sec_count: usize = 0;

    while (sec_count < Limits.max_sections) : (sec_count += 1) {
        scn = libelf.elf_nextscn(main_elf, scn);
        if (scn == null) break;
        var shdr: libelf.GElf_Shdr = undefined;
        if (libelf.gelf_getshdr(scn, &shdr) != null) {
            if (libelf.elf_strptr(main_elf, main_ehdr.e_shstrndx, shdr.sh_name)) |sec_name| {
                const name_slice = std.mem.span(sec_name);
                if (std.mem.eql(u8, name_slice, ".gnu_debuglink")) {
                    debuglink_count += 1;
                    if (shdr.sh_size > Limits.max_debuglink_size) {
                        empty_report.verdict = .ResourceLimitExceeded;
                        empty_report.error_message = ".gnu_debuglink exceeds size limit";
                        return empty_report;
                    }
                    if (libelf.elf_getdata(scn, null)) |data| {
                        if (data.d_buf != null and data.d_size > 0) {
                            const raw_ptr: [*]const u8 = @ptrCast(data.d_buf);
                            debuglink_payload_bytes = raw_ptr[0..data.d_size];
                        }
                    }
                }
            }
        }
    }

    empty_report.main_build_id = extractBuildId(allocator, main_elf.?, main_ehdr.e_shstrndx);

    if (debuglink_count == 0) {
        empty_report.verdict = .MissingDebuglink;
        empty_report.error_message = "Section .gnu_debuglink not found in main ELF";
        return empty_report;
    }

    if (debuglink_count > 1) {
        empty_report.verdict = .MalformedDebuglink;
        empty_report.error_message = "Duplicate .gnu_debuglink sections found";
        return empty_report;
    }

    const raw_data = debuglink_payload_bytes orelse {
        empty_report.verdict = .MalformedDebuglink;
        empty_report.error_message = "Section .gnu_debuglink is empty or unreadable";
        return empty_report;
    };

    const parsed = debuglink.parseDebuglink(raw_data, is_little) catch |err| {
        const msg = switch (err) {
            error.EmptySection => "Debuglink section is empty",
            error.MissingNulTerminator => "Missing NUL terminator in debuglink filename",
            error.InvalidPathSeparator => "Debuglink filename contains path separator",
            error.EmptyBasename => "Debuglink filename is empty",
            error.NonzeroPadding => "Debuglink padding contains non-zero bytes",
            error.TruncatedCrc => "Debuglink payload truncated before CRC field",
            error.TrailingBytes => "Debuglink payload contains trailing bytes after CRC",
        };
        empty_report.verdict = .MalformedDebuglink;
        empty_report.error_message = msg;
        return empty_report;
    };

    const name_copy = allocator.dupe(u8, parsed.filename) catch parsed.filename;
    empty_report.debuglink_name = name_copy;
    empty_report.expected_crc = parsed.crc;

    // Verify companion basename matches debuglink reference
    const comp_basename = getBasename(companion_path);
    if (!std.mem.eql(u8, comp_basename, parsed.filename)) {
        empty_report.verdict = .NameMismatch;
        empty_report.error_message = "Companion basename does not match .gnu_debuglink reference";
        return empty_report;
    }

    // 2. Inspect companion file via lstat (check symlink / non-regular)
    var comp_z_buf: [Limits.max_path_len + 1]u8 = undefined;
    const comp_z = toZ(&comp_z_buf, companion_path) catch {
        empty_report.verdict = .ResourceLimitExceeded;
        empty_report.error_message = "Cannot format companion path";
        return empty_report;
    };

    var comp_st_pre: libelf.Stat = undefined;
    if (libelf.lstat(comp_z.ptr, &comp_st_pre) != 0) {
        empty_report.verdict = .MissingCompanion;
        empty_report.error_message = "Companion debug file not found or inaccessible";
        return empty_report;
    }

    if ((comp_st_pre.st_mode & libelf.S_IFMT) == libelf.S_IFLNK) {
        empty_report.verdict = .SymlinkRejected;
        empty_report.error_message = "Companion is a symbolic link; symlinks are rejected";
        return empty_report;
    }

    if ((comp_st_pre.st_mode & libelf.S_IFMT) != libelf.S_IFREG) {
        empty_report.verdict = .NonRegularFile;
        empty_report.error_message = "Companion is not a regular file";
        return empty_report;
    }

    if (comp_st_pre.st_size > Limits.max_file_size) {
        empty_report.verdict = .ResourceLimitExceeded;
        empty_report.error_message = "Companion file exceeds 1 GiB size limit";
        return empty_report;
    }

    const comp_fd = libelf.open(comp_z.ptr, libelf.O_RDONLY);
    if (comp_fd < 0) {
        empty_report.verdict = .MissingCompanion;
        empty_report.error_message = "Cannot open companion debug file";
        return empty_report;
    }
    defer _ = libelf.close(comp_fd);

    var comp_st_post: libelf.Stat = undefined;
    if (libelf.fstat(comp_fd, &comp_st_post) != 0 or
        comp_st_post.st_size != comp_st_pre.st_size or
        comp_st_post.st_ino != comp_st_pre.st_ino or
        comp_st_post.st_dev != comp_st_pre.st_dev)
    {
        empty_report.verdict = .FileModifiedDuringRead;
        empty_report.error_message = "Companion file modified during opening barrier";
        return empty_report;
    }

    // Inspect companion ELF
    const comp_elf = libelf.elf_begin(comp_fd, libelf.ELF_C_READ, null);
    if (comp_elf == null) {
        empty_report.verdict = .IncompatibleElf;
        empty_report.error_message = "Companion file is not a valid ELF";
        return empty_report;
    }
    defer _ = libelf.elf_end(comp_elf);

    var comp_ehdr: libelf.GElf_Ehdr = undefined;
    if (libelf.gelf_getehdr(comp_elf, &comp_ehdr) == null) {
        empty_report.verdict = .IncompatibleElf;
        empty_report.error_message = "Cannot read companion ELF header";
        return empty_report;
    }

    // Check ELF compatibility (class, machine, byte order)
    if (comp_ehdr.e_ident[libelf.EI_CLASS] != main_ehdr.e_ident[libelf.EI_CLASS] or
        comp_ehdr.e_ident[libelf.EI_DATA] != main_ehdr.e_ident[libelf.EI_DATA] or
        comp_ehdr.e_machine != main_ehdr.e_machine)
    {
        empty_report.verdict = .IncompatibleElf;
        empty_report.error_message = "Companion ELF architecture or byte-order mismatch";
        return empty_report;
    }

    // Check companion debug sections
    var comp_scn: ?*libelf.Elf_Scn = null;
    var has_debug = false;
    var comp_sec_count: usize = 0;
    while (comp_sec_count < Limits.max_sections) : (comp_sec_count += 1) {
        comp_scn = libelf.elf_nextscn(comp_elf, comp_scn);
        if (comp_scn == null) break;
        var shdr: libelf.GElf_Shdr = undefined;
        if (libelf.gelf_getshdr(comp_scn, &shdr) != null) {
            if (libelf.elf_strptr(comp_elf, comp_ehdr.e_shstrndx, shdr.sh_name)) |sec_name| {
                const name_slice = std.mem.span(sec_name);
                if (std.mem.startsWith(u8, name_slice, ".debug_") or
                    std.mem.startsWith(u8, name_slice, ".zdebug_"))
                {
                    has_debug = true;
                    break;
                }
            }
        }
    }
    empty_report.has_debug_sections = has_debug;

    empty_report.companion_build_id = extractBuildId(allocator, comp_elf.?, comp_ehdr.e_shstrndx);
    if (empty_report.main_build_id != null and empty_report.companion_build_id != null) {
        empty_report.build_ids_agree = std.mem.eql(u8, empty_report.main_build_id.?, empty_report.companion_build_id.?);
    }

    if (!has_debug) {
        empty_report.verdict = .MissingDebugSections;
        empty_report.error_message = "Companion file does not contain expected .debug_* sections";
        return empty_report;
    }

    // 3. Compute companion CRC32 across all bytes of file
    _ = libelf.lseek(comp_fd, 0, 0); // SEEK_SET
    var read_buffer: [65536]u8 = undefined;
    var computed_crc: u32 = 0;
    var first_chunk = true;

    while (true) {
        const bytes_read = libelf.read(comp_fd, &read_buffer, read_buffer.len);
        if (bytes_read < 0) {
            empty_report.verdict = .OpenFailed;
            empty_report.error_message = "Error reading companion file contents";
            return empty_report;
        }
        if (bytes_read == 0) break;

        const slice = read_buffer[0..@intCast(bytes_read)];
        if (first_chunk) {
            computed_crc = crc.calculateCrc(slice);
            first_chunk = false;
        } else {
            computed_crc = crc.updateCrc(computed_crc, slice);
        }
    }

    empty_report.actual_crc = computed_crc;

    // Check detected change barrier after read
    var comp_st_final: libelf.Stat = undefined;
    if (libelf.fstat(comp_fd, &comp_st_final) != 0 or
        comp_st_final.st_size != comp_st_post.st_size or
        comp_st_final.st_mtime != comp_st_post.st_mtime or
        comp_st_final.st_ino != comp_st_post.st_ino)
    {
        empty_report.verdict = .FileModifiedDuringRead;
        empty_report.error_message = "Companion file modified during CRC read";
        return empty_report;
    }

    var main_st_final: libelf.Stat = undefined;
    if (libelf.fstat(main_fd, &main_st_final) != 0 or
        main_st_final.st_size != main_st_post.st_size or
        main_st_final.st_mtime != main_st_post.st_mtime or
        main_st_final.st_ino != main_st_post.st_ino)
    {
        empty_report.verdict = .FileModifiedDuringRead;
        empty_report.error_message = "Main ELF file modified during audit";
        return empty_report;
    }

    // 4. Compare CRCs
    if (computed_crc != parsed.crc) {
        empty_report.verdict = .CrcMismatch;
        empty_report.error_message = "Companion CRC does not match .gnu_debuglink checksum";
        return empty_report;
    }

    empty_report.verdict = .Matched;
    empty_report.error_message = null;
    return empty_report;
}
