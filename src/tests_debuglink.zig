const std = @import("std");
const debuglink = @import("debuglink.zig");

test "valid little-endian debuglink payload" {
    const payload = "sample.debug\x00\x00\x00\x00\x8a\x5d\x42\xff";
    const res = try debuglink.parseDebuglink(payload, true);

    try std.testing.expectEqualStrings("sample.debug", res.filename);
    try std.testing.expectEqual(@as(u32, 0xff425d8a), res.crc);
    try std.testing.expectEqual(@as(usize, 3), res.padding_bytes);
}

test "valid big-endian debuglink payload" {
    const payload = "sample.debug\x00\x00\x00\x00\xff\x42\x5d\x8a";
    const res = try debuglink.parseDebuglink(payload, false);

    try std.testing.expectEqualStrings("sample.debug", res.filename);
    try std.testing.expectEqual(@as(u32, 0xff425d8a), res.crc);
    try std.testing.expectEqual(@as(usize, 3), res.padding_bytes);
}

test "valid payload with 4-byte padding boundary" {
    const payload = "abc\x00\x12\x34\x56\x78";
    const res = try debuglink.parseDebuglink(payload, true);

    try std.testing.expectEqualStrings("abc", res.filename);
    try std.testing.expectEqual(@as(u32, 0x78563412), res.crc);
    try std.testing.expectEqual(@as(usize, 0), res.padding_bytes);
}

test "reject empty section" {
    const err = debuglink.parseDebuglink("", true);
    try std.testing.expectError(error.EmptySection, err);
}

test "reject truncated section" {
    const err = debuglink.parseDebuglink("a\x00", true);
    try std.testing.expectError(error.TruncatedCrc, err);
}

test "reject missing nul terminator" {
    const payload = "abcdefghijklmnop";
    const err = debuglink.parseDebuglink(payload, true);
    try std.testing.expectError(error.MissingNulTerminator, err);
}

test "reject empty basename" {
    const payload = "\x00\x00\x00\x00\x12\x34\x56\x78";
    const err = debuglink.parseDebuglink(payload, true);
    try std.testing.expectError(error.EmptyBasename, err);
}

test "reject path separators in basename" {
    const payload_slash = "dir/sample.debug\x00\x00\x00\x12\x34\x56\x78";
    try std.testing.expectError(error.InvalidPathSeparator, debuglink.parseDebuglink(payload_slash, true));

    const payload_bslash = "dir\\sample.debug\x00\x00\x00\x12\x34\x56\x78";
    try std.testing.expectError(error.InvalidPathSeparator, debuglink.parseDebuglink(payload_bslash, true));

    const payload_colon = "c:sample.debug\x00\x00\x12\x34\x56\x78";
    try std.testing.expectError(error.InvalidPathSeparator, debuglink.parseDebuglink(payload_colon, true));
}

test "reject nonzero padding bytes" {
    const payload = "sample.debug\x00\x00\x01\x00\x12\x34\x56\x78";
    const err = debuglink.parseDebuglink(payload, true);
    try std.testing.expectError(error.NonzeroPadding, err);
}

test "reject trailing bytes after crc" {
    const payload = "sample.debug\x00\x00\x00\x00\x12\x34\x56\x78\x99\xaa";
    const err = debuglink.parseDebuglink(payload, true);
    try std.testing.expectError(error.TrailingBytes, err);
}
