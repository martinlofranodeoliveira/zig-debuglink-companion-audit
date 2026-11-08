const std = @import("std");
const crc = @import("crc.zig");

test "crc32 empty slice" {
    const res = crc.calculateCrc("");
    try std.testing.expectEqual(@as(u32, 0x00000000), res);
}

test "crc32 standard test vector 123456789" {
    const res = crc.calculateCrc("123456789");
    try std.testing.expectEqual(@as(u32, 0xCBF43926), res);
}

test "crc32 pangram" {
    const res = crc.calculateCrc("The quick brown fox jumps over the lazy dog");
    try std.testing.expectEqual(@as(u32, 0x414FA339), res);
}

test "crc32 incremental update matches one-shot" {
    const data = "Deterministic GNU debuglink companion CRC verification under strict bounds.";
    const oneshot = crc.calculateCrc(data);

    var incremental = crc.calculateCrc(data[0..15]);
    incremental = crc.updateCrc(incremental, data[15..32]);
    incremental = crc.updateCrc(incremental, data[32..]);

    try std.testing.expectEqual(oneshot, incremental);
}
