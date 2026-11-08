const std = @import("std");
const libelf = @import("libelf_types.zig");
const auditor = @import("auditor.zig");

test "auditor matches real objcopy split fixture" {
    const allocator = std.testing.allocator;
    const report = auditor.auditFiles(allocator, "fixtures/sample.bin", "fixtures/sample.debug");
    defer report.deinit(allocator);

    try std.testing.expectEqual(auditor.Verdict.Matched, report.verdict);
    try std.testing.expect(report.has_debug_sections);
    try std.testing.expect(report.expected_crc != null);
    try std.testing.expect(report.actual_crc != null);
    try std.testing.expectEqual(report.expected_crc.?, report.actual_crc.?);
    try std.testing.expectEqualStrings("sample.debug", report.debuglink_name.?);
}

test "auditor detects missing debuglink section" {
    const allocator = std.testing.allocator;
    const report = auditor.auditFiles(allocator, "fixtures/sample.full", "fixtures/sample.debug");
    defer report.deinit(allocator);

    try std.testing.expectEqual(auditor.Verdict.MissingDebuglink, report.verdict);
}

test "auditor detects missing companion file" {
    const allocator = std.testing.allocator;
    const report = auditor.auditFiles(allocator, "fixtures/sample.bin", "fixtures/nonexistent_dir/sample.debug");
    defer report.deinit(allocator);

    try std.testing.expectEqual(auditor.Verdict.MissingCompanion, report.verdict);
}

test "auditor rejects symlink companion" {
    const allocator = std.testing.allocator;
    _ = libelf.mkdir("/tmp/sym_test", 0o755);
    const sym = "/tmp/sym_test/sample.debug";
    _ = libelf.unlink(sym);
    if (libelf.symlink("fixtures/sample.debug", sym) == 0) {
        const report = auditor.auditFiles(allocator, "fixtures/sample.bin", sym);
        defer report.deinit(allocator);
        try std.testing.expectEqual(auditor.Verdict.SymlinkRejected, report.verdict);
    }
}
