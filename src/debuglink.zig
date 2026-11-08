const std = @import("std");

pub const DebuglinkError = error{
    EmptySection,
    MissingNulTerminator,
    InvalidPathSeparator,
    EmptyBasename,
    NonzeroPadding,
    TruncatedCrc,
    TrailingBytes,
};

pub const DebuglinkPayload = struct {
    filename: []const u8,
    crc: u32,
    padding_bytes: usize,
};

/// Parses and validates a raw .gnu_debuglink section payload according to GNU BFD specifications.
pub fn parseDebuglink(data: []const u8, is_little_endian: bool) DebuglinkError!DebuglinkPayload {
    if (data.len == 0) return DebuglinkError.EmptySection;

    // Minimum size: 1 char filename + 1 NUL + 2 padding + 4 CRC = 8 bytes minimum
    // (e.g. "a\0\0\0<CRC>")
    if (data.len < 5) return DebuglinkError.TruncatedCrc;

    // Find the first NUL terminator
    var nul_idx: ?usize = null;
    for (data, 0..) |b, i| {
        if (b == 0) {
            nul_idx = i;
            break;
        }
    }

    const n_idx = nul_idx orelse return DebuglinkError.MissingNulTerminator;
    if (n_idx == 0) return DebuglinkError.EmptyBasename;

    const filename = data[0..n_idx];

    // Verify filename has no directory components
    for (filename) |b| {
        if (b == '/' or b == '\\' or b == ':') {
            return DebuglinkError.InvalidPathSeparator;
        }
    }

    // Alignment calculation: filename + NUL terminator
    const string_len = n_idx + 1;
    const remainder = string_len % 4;
    const pad_len: usize = if (remainder == 0) 0 else 4 - remainder;

    const crc_offset = string_len + pad_len;
    if (crc_offset + 4 > data.len) {
        return DebuglinkError.TruncatedCrc;
    }

    // Verify all padding bytes are strictly 0x00
    for (data[string_len..crc_offset]) |pad_byte| {
        if (pad_byte != 0) {
            return DebuglinkError.NonzeroPadding;
        }
    }

    // Total section size must exactly equal crc_offset + 4
    if (data.len > crc_offset + 4) {
        return DebuglinkError.TrailingBytes;
    }

    // Extract 4-byte CRC in specified endianness
    const crc_bytes = data[crc_offset .. crc_offset + 4];
    const crc: u32 = if (is_little_endian)
        std.mem.readInt(u32, crc_bytes[0..4], .little)
    else
        std.mem.readInt(u32, crc_bytes[0..4], .big);

    return DebuglinkPayload{
        .filename = filename,
        .crc = crc,
        .padding_bytes = pad_len,
    };
}
