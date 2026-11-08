const std = @import("std");
const libelf = @import("libelf_types.zig");
const crc = @import("crc.zig");
const debuglink = @import("debuglink.zig");
const auditor = @import("auditor.zig");

pub const ManifestEntry = struct {
    id: ?[]const u8 = null,
    elf: []const u8,
    companion: []const u8,
};

pub const Manifest = struct {
    entries: []const ManifestEntry,
};

pub fn toZ(buf: []u8, slice: []const u8) ![:0]const u8 {
    if (slice.len >= buf.len) return error.PathTooLong;
    @memcpy(buf[0..slice.len], slice);
    buf[slice.len] = 0;
    return buf[0..slice.len :0];
}

pub fn readFileToSlice(allocator: std.mem.Allocator, path: []const u8, max_size: usize) ![]u8 {
    if (path.len == 0 or path.len > 4096) return error.InvalidPath;
    var path_z_buf: [4097]u8 = undefined;
    const path_z = try toZ(&path_z_buf, path);

    var st: libelf.Stat = undefined;
    if (libelf.lstat(path_z.ptr, &st) != 0) return error.FileNotFound;
    if ((st.st_mode & libelf.S_IFMT) != libelf.S_IFREG) return error.NotRegularFile;
    if (st.st_size < 0 or @as(usize, @intCast(st.st_size)) > max_size) return error.FileTooLarge;

    const fd = libelf.open(path_z.ptr, libelf.O_RDONLY);
    if (fd < 0) return error.OpenFailed;
    defer _ = libelf.close(fd);

    const size: usize = @intCast(st.st_size);
    const buf = try allocator.alloc(u8, size);
    errdefer allocator.free(buf);

    var total_read: usize = 0;
    while (total_read < size) {
        const n = libelf.read(fd, buf.ptr + total_read, size - total_read);
        if (n <= 0) return error.ReadFailed;
        total_read += @intCast(n);
    }
    return buf;
}

pub const FdWriter = struct {
    fd: c_int,

    pub const Error = error{WriteFailed};

    pub fn writeAll(self: FdWriter, bytes: []const u8) Error!void {
        var total: usize = 0;
        while (total < bytes.len) {
            const n = libelf.write(self.fd, bytes.ptr + total, bytes.len - total);
            if (n < 0) return error.WriteFailed;
            total += @intCast(n);
        }
    }

    pub fn print(self: FdWriter, comptime fmt: []const u8, args: anytype) Error!void {
        var buf: [4096]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, fmt, args) catch return error.WriteFailed;
        try self.writeAll(slice);
    }
};

pub const stdout = FdWriter{ .fd = 1 };
pub const stderr = FdWriter{ .fd = 2 };

fn printUsage(writer: FdWriter) !void {
    try writer.writeAll(
        \\Debuglink Companion Audit - GNU ELF .gnu_debuglink companion verifier
        \\
        \\Usage:
        \\  zig-debuglink-companion-audit [options]
        \\
        \\Options:
        \\  --manifest <path>     Path to JSON manifest listing ELF/companion pairs
        \\  --elf <path>          Path to main ELF executable or shared library
        \\  --debug <path>        Path to companion debug file (.debug)
        \\  --json                Emit structured JSON report to standard output
        \\  --assert              Run self-contained asserting verification suite
        \\  --help, -h            Show this help text
        \\
        \\Manifest JSON format:
        \\  {
        \\    "entries": [
        \\      {
        \\        "id": "my-target",
        \\        "elf": "path/to/main.bin",
        \\        "companion": "path/to/main.debug"
        \\      }
        \\    ]
        \\  }
        \\
    );
}

fn printReportText(writer: FdWriter, r: auditor.AuditReport, id: ?[]const u8) !void {
    const verdict_str = @tagName(r.verdict);
    if (id) |name| {
        try writer.print("[{s}] Verdict: {s}\n", .{ name, verdict_str });
    } else {
        try writer.print("Verdict: {s}\n", .{verdict_str});
    }
    try writer.print("  Main ELF:          {s}\n", .{r.main_elf});
    try writer.print("  Companion:         {s}\n", .{r.companion});
    if (r.debuglink_name) |dn| {
        try writer.print("  Debuglink Name:    {s}\n", .{dn});
    }
    if (r.expected_crc) |exp| {
        try writer.print("  Expected CRC32:    0x{x:0>8}\n", .{exp});
    }
    if (r.actual_crc) |act| {
        try writer.print("  Computed CRC32:    0x{x:0>8}\n", .{act});
    }
    if (r.elf_class != 0) {
        const class_str: []const u8 = switch (r.elf_class) {
            1 => "ELF32",
            2 => "ELF64",
            else => "Unknown",
        };
        try writer.print("  ELF Class:         {s}\n", .{class_str});
    }
    if (r.elf_machine != 0) {
        try writer.print("  ELF Machine:       0x{x:0>4}\n", .{r.elf_machine});
    }
    try writer.print("  Debug Sections:    {}\n", .{r.has_debug_sections});
    if (r.main_build_id) |bid| {
        try writer.print("  Main Build-ID:     {s}\n", .{bid});
    }
    if (r.companion_build_id) |bid| {
        try writer.print("  Companion Build-ID:{s}\n", .{bid});
    }
    if (r.build_ids_agree) |agree| {
        try writer.print("  Build-IDs Match:   {}\n", .{agree});
    }
    if (r.error_message) |msg| {
        try writer.print("  Details:           {s}\n", .{msg});
    }
    try writer.writeAll("\n");
}

fn serializeReportJson(allocator: std.mem.Allocator, reports: []const auditor.AuditReport, ids: []const ?[]const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    try list.appendSlice(allocator, "[\n");
    for (reports, 0..) |r, i| {
        if (i > 0) try list.appendSlice(allocator, ",\n");
        try list.appendSlice(allocator, "  {\n");
        if (ids[i]) |id| {
            var buf: [512]u8 = undefined;
            const line = try std.fmt.bufPrint(&buf, "    \"id\": \"{s}\",\n", .{id});
            try list.appendSlice(allocator, line);
        }
        var buf2: [1024]u8 = undefined;
        const v_line = try std.fmt.bufPrint(&buf2, "    \"verdict\": \"{s}\",\n    \"main_elf\": \"{s}\",\n    \"companion\": \"{s}\",\n", .{
            @tagName(r.verdict), r.main_elf, r.companion,
        });
        try list.appendSlice(allocator, v_line);

        if (r.debuglink_name) |dn| {
            const dn_line = try std.fmt.bufPrint(&buf2, "    \"debuglink_name\": \"{s}\",\n", .{dn});
            try list.appendSlice(allocator, dn_line);
        } else {
            try list.appendSlice(allocator, "    \"debuglink_name\": null,\n");
        }

        if (r.expected_crc) |exp| {
            const exp_line = try std.fmt.bufPrint(&buf2, "    \"expected_crc\": {},\n", .{exp});
            try list.appendSlice(allocator, exp_line);
        } else {
            try list.appendSlice(allocator, "    \"expected_crc\": null,\n");
        }

        if (r.actual_crc) |act| {
            const act_line = try std.fmt.bufPrint(&buf2, "    \"actual_crc\": {},\n", .{act});
            try list.appendSlice(allocator, act_line);
        } else {
            try list.appendSlice(allocator, "    \"actual_crc\": null,\n");
        }

        const cls_line = try std.fmt.bufPrint(&buf2, "    \"elf_class\": {},\n    \"elf_machine\": {},\n    \"has_debug_sections\": {},\n", .{
            r.elf_class, r.elf_machine, r.has_debug_sections,
        });
        try list.appendSlice(allocator, cls_line);

        if (r.main_build_id) |bid| {
            const bid_line = try std.fmt.bufPrint(&buf2, "    \"main_build_id\": \"{s}\",\n", .{bid});
            try list.appendSlice(allocator, bid_line);
        } else {
            try list.appendSlice(allocator, "    \"main_build_id\": null,\n");
        }

        if (r.companion_build_id) |bid| {
            const bid_line = try std.fmt.bufPrint(&buf2, "    \"companion_build_id\": \"{s}\",\n", .{bid});
            try list.appendSlice(allocator, bid_line);
        } else {
            try list.appendSlice(allocator, "    \"companion_build_id\": null,\n");
        }

        if (r.build_ids_agree) |agree| {
            const agree_line = try std.fmt.bufPrint(&buf2, "    \"build_ids_agree\": {},\n", .{agree});
            try list.appendSlice(allocator, agree_line);
        } else {
            try list.appendSlice(allocator, "    \"build_ids_agree\": null,\n");
        }

        if (r.error_message) |msg| {
            const msg_line = try std.fmt.bufPrint(&buf2, "    \"error_message\": \"{s}\"\n", .{msg});
            try list.appendSlice(allocator, msg_line);
        } else {
            try list.appendSlice(allocator, "    \"error_message\": null\n");
        }

        try list.appendSlice(allocator, "  }");
    }
    try list.appendSlice(allocator, "\n]\n");
    return list.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init.Minimal) !u8 {
    const allocator = std.heap.c_allocator;
    var args = init.args.iterate();
    _ = args.next(); // Skip binary name

    var manifest_path: ?[]const u8 = null;
    var elf_path: ?[]const u8 = null;
    var debug_path: ?[]const u8 = null;
    var json_output = false;
    var assert_mode = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "--assert")) {
            assert_mode = true;
        } else if (std.mem.eql(u8, arg, "--manifest")) {
            manifest_path = args.next() orelse {
                stderr.print("Error: --manifest requires a path argument\n", .{}) catch {};
                return 2;
            };
        } else if (std.mem.eql(u8, arg, "--elf")) {
            elf_path = args.next() orelse {
                stderr.print("Error: --elf requires a path argument\n", .{}) catch {};
                return 2;
            };
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug_path = args.next() orelse {
                stderr.print("Error: --debug requires a path argument\n", .{}) catch {};
                return 2;
            };
        } else {
            stderr.print("Unknown option: {s}\nRun with --help for options\n", .{arg}) catch {};
            return 2;
        }
    }

    if (assert_mode) {
        return runAssertionSuite(allocator, json_output);
    }

    var entries: std.ArrayList(ManifestEntry) = .empty;
    defer entries.deinit(allocator);

    if (manifest_path) |m_path| {
        const raw_json = readFileToSlice(allocator, m_path, 1024 * 1024) catch |err| {
            stderr.print("Error reading manifest {s}: {}\n", .{ m_path, err }) catch {};
            return 2;
        };
        defer allocator.free(raw_json);

        // Try parsing as {"entries": [...]}
        var parsed = std.json.parseFromSlice(Manifest, allocator, raw_json, .{ .ignore_unknown_fields = true }) catch null;
        if (parsed) |*p| {
            defer p.deinit();
            for (p.value.entries) |entry| {
                try entries.append(allocator, ManifestEntry{
                    .id = if (entry.id) |id| try allocator.dupe(u8, id) else null,
                    .elf = try allocator.dupe(u8, entry.elf),
                    .companion = try allocator.dupe(u8, entry.companion),
                });
            }
        } else {
            // Try parsing directly as [ManifestEntry]
            var list_parsed = std.json.parseFromSlice([]ManifestEntry, allocator, raw_json, .{ .ignore_unknown_fields = true }) catch |err| {
                stderr.print("Error parsing manifest JSON: {}\n", .{err}) catch {};
                return 2;
            };
            defer list_parsed.deinit();
            for (list_parsed.value) |entry| {
                try entries.append(allocator, ManifestEntry{
                    .id = if (entry.id) |id| try allocator.dupe(u8, id) else null,
                    .elf = try allocator.dupe(u8, entry.elf),
                    .companion = try allocator.dupe(u8, entry.companion),
                });
            }
        }
    } else if (elf_path != null and debug_path != null) {
        try entries.append(allocator, ManifestEntry{
            .id = null,
            .elf = elf_path.?,
            .companion = debug_path.?,
        });
    } else {
        stderr.print("Error: Specify either --manifest <path> or both --elf <path> and --debug <path> (or --assert)\n", .{}) catch {};
        return 2;
    }

    if (entries.items.len == 0) {
        stderr.print("Error: Manifest contains no entries\n", .{}) catch {};
        return 2;
    }

    var reports: std.ArrayList(auditor.AuditReport) = .empty;
    defer reports.deinit(allocator);

    var ids: std.ArrayList(?[]const u8) = .empty;
    defer ids.deinit(allocator);

    var all_matched = true;

    for (entries.items) |entry| {
        const report = auditor.auditFiles(allocator, entry.elf, entry.companion);
        if (report.verdict != .Matched) {
            all_matched = false;
        }
        try reports.append(allocator, report);
        try ids.append(allocator, entry.id);
    }

    if (json_output) {
        const json_slice = try serializeReportJson(allocator, reports.items, ids.items);
        defer allocator.free(json_slice);
        try stdout.print("{s}\n", .{json_slice});
    } else {
        for (reports.items, 0..) |r, i| {
            try printReportText(stdout, r, ids.items[i]);
        }
    }

    return if (all_matched) 0 else 1;
}

fn runAssertionSuite(allocator: std.mem.Allocator, json_output: bool) u8 {
    var pass_count: usize = 0;
    var fail_count: usize = 0;

    if (!json_output) {
        stdout.print("=== Running Built-in Debuglink Companion Assertions ===\n", .{}) catch {};
    }

    // Assertion 1: Valid split fixture
    {
        const r = auditor.auditFiles(allocator, "fixtures/sample.bin", "fixtures/sample.debug");
        if (r.verdict == .Matched and r.has_debug_sections and r.expected_crc != null and r.actual_crc != null and r.expected_crc.? == r.actual_crc.?) {
            pass_count += 1;
            if (!json_output) stdout.print("  [PASS] 1. Cleanly split ELF & companion match with exact CRC\n", .{}) catch {};
        } else {
            fail_count += 1;
            if (!json_output) stdout.print("  [FAIL] 1. Cleanly split ELF fixture: verdict={s}\n", .{@tagName(r.verdict)}) catch {};
        }
    }

    // Assertion 2: Companion byte change causes CRC mismatch
    {
        // Copy companion to temporary corrupted version
        const comp_bytes = readFileToSlice(allocator, "fixtures/sample.debug", 1024 * 1024) catch null;
        if (comp_bytes) |bytes| {
            defer allocator.free(bytes);
            // Flip byte 16
            bytes[16] ^= 0xFF;
            _ = libelf.mkdir("/tmp/corrupt", 0o755);
            const tmp_path = "/tmp/corrupt/sample.debug";
            _ = libelf.unlink(tmp_path);
            const fd = libelf.open(tmp_path, 0x241, @as(u32, 0o644)); // O_WRONLY | O_CREAT | O_TRUNC
            if (fd >= 0) {
                _ = libelf.write(fd, bytes.ptr, bytes.len);
                _ = libelf.close(fd);

                const r = auditor.auditFiles(allocator, "fixtures/sample.bin", tmp_path);
                if (r.verdict == .CrcMismatch and r.expected_crc.? != r.actual_crc.?) {
                    pass_count += 1;
                    if (!json_output) stdout.print("  [PASS] 2. Single byte change in companion produces CrcMismatch\n", .{}) catch {};
                } else {
                    fail_count += 1;
                    if (!json_output) stdout.print("  [FAIL] 2. Expected CrcMismatch, got {s}\n", .{@tagName(r.verdict)}) catch {};
                }
            } else {
                fail_count += 1;
            }
        } else {
            fail_count += 1;
        }
    }

    // Assertion 3: Companion name mismatch
    {
        const comp_bytes = readFileToSlice(allocator, "fixtures/sample.debug", 1024 * 1024) catch null;
        if (comp_bytes) |bytes| {
            defer allocator.free(bytes);
            const tmp_path = "/tmp/other_name.debug";
            _ = libelf.unlink(tmp_path);
            const fd = libelf.open(tmp_path, 0x241, @as(u32, 0o644));
            if (fd >= 0) {
                _ = libelf.write(fd, bytes.ptr, bytes.len);
                _ = libelf.close(fd);

                const r = auditor.auditFiles(allocator, "fixtures/sample.bin", tmp_path);
                if (r.verdict == .NameMismatch) {
                    pass_count += 1;
                    if (!json_output) stdout.print("  [PASS] 3. Incorrect companion basename produces NameMismatch\n", .{}) catch {};
                } else {
                    fail_count += 1;
                    if (!json_output) stdout.print("  [FAIL] 3. Expected NameMismatch, got {s}\n", .{@tagName(r.verdict)}) catch {};
                }
            } else {
                fail_count += 1;
            }
        } else {
            fail_count += 1;
        }
    }

    // Assertion 4: Missing debug sections
    {
        // Create a companion named sample.debug that has no debug sections (e.g. sample.bin stripped).
        const bin_bytes = readFileToSlice(allocator, "fixtures/sample.bin", 1024 * 1024) catch null;
        if (bin_bytes) |bytes| {
            defer allocator.free(bytes);
            _ = libelf.mkdir("/tmp/nodebug", 0o755);
            const tmp_path = "/tmp/nodebug/sample.debug";
            _ = libelf.unlink(tmp_path);
            const fd = libelf.open(tmp_path, 0x241, @as(u32, 0o644));
            if (fd >= 0) {
                _ = libelf.write(fd, bytes.ptr, bytes.len);
                _ = libelf.close(fd);

                const r2 = auditor.auditFiles(allocator, "fixtures/sample.bin", tmp_path);
                if (r2.verdict == .MissingDebugSections) {
                    pass_count += 1;
                    if (!json_output) stdout.print("  [PASS] 4. Companion lacking .debug_* sections produces MissingDebugSections\n", .{}) catch {};
                } else {
                    fail_count += 1;
                    if (!json_output) stdout.print("  [FAIL] 4. Expected MissingDebugSections, got {s}\n", .{@tagName(r2.verdict)}) catch {};
                }
            } else {
                fail_count += 1;
            }
        } else {
            fail_count += 1;
        }
    }

    // Assertion 5: Missing .gnu_debuglink section
    {
        // fixtures/sample.full has no .gnu_debuglink
        const r = auditor.auditFiles(allocator, "fixtures/sample.full", "fixtures/sample.debug");
        if (r.verdict == .MissingDebuglink) {
            pass_count += 1;
            if (!json_output) stdout.print("  [PASS] 5. Main ELF without .gnu_debuglink produces MissingDebuglink\n", .{}) catch {};
        } else {
            fail_count += 1;
            if (!json_output) stdout.print("  [FAIL] 5. Expected MissingDebuglink, got {s}\n", .{@tagName(r.verdict)}) catch {};
        }
    }

    // Assertion 6: Missing companion file
    {
        const r2 = auditor.auditFiles(allocator, "fixtures/sample.bin", "fixtures/missing_dir/sample.debug");
        if (r2.verdict == .MissingCompanion) {
            pass_count += 1;
            if (!json_output) stdout.print("  [PASS] 6. Inaccessible companion produces MissingCompanion\n", .{}) catch {};
        } else {
            fail_count += 1;
            if (!json_output) stdout.print("  [FAIL] 6. Expected MissingCompanion, got {s}\n", .{@tagName(r2.verdict)}) catch {};
        }
    }

    // Assertion 7: Symlink rejection
    {
        _ = libelf.mkdir("/tmp/symdir", 0o755);
        const sym_path = "/tmp/symdir/sample.debug";
        _ = libelf.unlink(sym_path);
        if (libelf.symlink("fixtures/sample.debug", sym_path) == 0) {
            const r = auditor.auditFiles(allocator, "fixtures/sample.bin", sym_path);
            if (r.verdict == .SymlinkRejected) {
                pass_count += 1;
                if (!json_output) stdout.print("  [PASS] 7. Symlink companion correctly rejected (SymlinkRejected)\n", .{}) catch {};
            } else {
                fail_count += 1;
                if (!json_output) stdout.print("  [FAIL] 7. Symlink check failed: {s}\n", .{@tagName(r.verdict)}) catch {};
            }
        } else {
            fail_count += 1;
        }
    }

    // Assertion 8: Pure payload test vectors (little-endian & big-endian)
    {
        // Little endian: name "test.debug\0" (11 bytes) + 1 zero pad (12 bytes) + 4 bytes CRC
        const le_payload = "test.debug\x00\x00\x12\x34\x56\x78";
        const parsed_le = debuglink.parseDebuglink(le_payload, true) catch null;

        // Big endian: same string + big-endian CRC
        const be_payload = "test.debug\x00\x00\x78\x56\x34\x12";
        const parsed_be = debuglink.parseDebuglink(be_payload, false) catch null;

        if (parsed_le != null and parsed_le.?.crc == 0x78563412 and
            parsed_be != null and parsed_be.?.crc == 0x78563412 and
            std.mem.eql(u8, parsed_le.?.filename, "test.debug"))
        {
            pass_count += 1;
            if (!json_output) stdout.print("  [PASS] 8. Target-endian CRC decoding (little and big endian)\n", .{}) catch {};
        } else {
            fail_count += 1;
            if (!json_output) stdout.print("  [FAIL] 8. Endian CRC decoding vector failure\n", .{}) catch {};
        }
    }

    // Assertion 9: Malformed debuglink payload rejection
    {
        const no_nul = "test.debug1234";
        const nonzero_pad = "test.debug\x00\xFF\x12\x34\x56\x78";
        const path_sep = "dir/test.debug\x00\x00\x12\x34\x56\x78";
        const truncated = "test.debug\x00\x00\x12";

        const err1 = debuglink.parseDebuglink(no_nul, true);
        const err2 = debuglink.parseDebuglink(nonzero_pad, true);
        const err3 = debuglink.parseDebuglink(path_sep, true);
        const err4 = debuglink.parseDebuglink(truncated, true);

        if (err1 == error.MissingNulTerminator and
            err2 == error.NonzeroPadding and
            err3 == error.InvalidPathSeparator and
            err4 == error.TruncatedCrc)
        {
            pass_count += 1;
            if (!json_output) stdout.print("  [PASS] 9. Malformed debuglink vectors rejected with structural errors\n", .{}) catch {};
        } else {
            fail_count += 1;
            if (!json_output) stdout.print("  [FAIL] 9. Malformed payload detection error\n", .{}) catch {};
        }
    }

    if (json_output) {
        stdout.print("{{\"pass_count\": {}, \"fail_count\": {}, \"status\": \"{s}\"}}\n", .{
            pass_count,
            fail_count,
            if (fail_count == 0) "success" else "failure",
        }) catch {};
    } else {
        stdout.print("=== Summary: {} passed, {} failed ===\n\n", .{ pass_count, fail_count }) catch {};
    }

    return if (fail_count == 0) 0 else 1;
}
