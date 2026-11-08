const std = @import("std");

/// Precomputed IEEE 802.3 CRC-32 lookup table (polynomial 0xEDB88320).
const TABLE: [256]u32 = blk: {
    @setEvalBranchQuota(5000);
    var table: [256]u32 = undefined;
    for (0..256) |i| {
        var c: u32 = @intCast(i);
        for (0..8) |_| {
            if ((c & 1) != 0) {
                c = 0xEDB88320 ^ (c >> 1);
            } else {
                c = c >> 1;
            }
        }
        table[i] = c;
    }
    break :blk table;
};

/// Computes GNU debuglink CRC32 over a byte slice.
/// Follows IEEE 802.3 / BFD calc_gnu_debuglink_crc32.
pub fn calculateCrc(bytes: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (bytes) |b| {
        const idx = @as(u8, @truncate(crc ^ b));
        crc = TABLE[idx] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
}

/// Incrementally updates CRC32 state with a chunk of bytes.
pub fn updateCrc(current_crc: u32, chunk: []const u8) u32 {
    var crc = current_crc ^ 0xFFFFFFFF;
    for (chunk) |b| {
        const idx = @as(u8, @truncate(crc ^ b));
        crc = TABLE[idx] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
}
