const PNG = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const toBytes = std.mem.toBytes;
const nativeToBig = std.mem.nativeToBig;

// https://www.libpng.org/pub/png/spec/pngspec-index.html
// https://www.libpng.org/pub/png/spec/1.2/
// https://www.w3.org/TR/png-3/

// NOTE: like tga, minimal implementation just for what we need

const Signature = [8]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
const ColorType = enum(u8) { Greyscale, Truecolor, IndexedColor, GreyscaleAlpha, TruecolorAlpha };

// IHDR
Width: u32,
Height: u32,
BitDepth: u8,
ColorType: ColorType,
// CompressionMethod: u8,
// FilterMethod: u8,
// InterlaceMethod: u8,

// WRITING

//pub fn WriteIHDR(self: *PNG, writer: anytype) !void {
//    try writer.writeIntBig(u32, 13); // chunk data length
//    const c = crcWriter(writer);
//    var cw = c.writer();
//    try cw.write(&[4]u8{ 'I', 'H', 'D', 'R' });
//    try cw.writeIntBig(u32, self.Width); // Width
//    try cw.writeIntBig(u32, self.Height); // Height
//    try cw.writeIntBig(u8, self.BitDepth); // BitDepth
//    try cw.writeIntBig(u8, self.ColorType); // ColorType
//    try cw.writeIntBig(u8, 0); // CompressionMethod
//    try cw.writeIntBig(u8, 0); // FilterMethod
//    try cw.writeIntBig(u8, 0); // InterlaceMethod
//    try writer.writeIntBig(u32, c.crc);
//}
//
//pub fn WriteIEND(_: *PNG, writer: anytype) !void {
//    try writer.writeIntBig(u32, 0); // chunk data length
//    const c = crcWriter(writer);
//    var cw = c.writer();
//    try cw.write(&[4]u8{ 'I', 'E', 'N', 'D' });
//    try writer.writeIntBig(u32, c.crc);
//}
//
//// FIXME: figure out compressor, not sure if std zlib/deflate suitable for png, also
//// seems to need allocators
//// TODO: impl
//pub fn WriteIDAT(_: *PNG, writer: anytype, _: Allocator, _: []const u8) !void {
//    // const cmp = std.compress.zlib.compressStream(null, writer, );
//    try writer.writeIntBig(u32, 0xFFFFFFFF); // chunk data length
//    const c = crcWriter(writer);
//    var cw = c.writer();
//    try cw.write(&[4]u8{ 'I', 'D', 'A', 'T' });
//    try writer.writeIntBig(u32, c.crc);
//}

// READING

pub fn Read(reader: anytype) !void {
    const signature: [8]u8 = sig: {
        var signature: [8]u8 = undefined;
        _ = try reader.read(&signature);
        break :sig signature;
    };
    if (!std.mem.eql(u8, &signature, &Signature)) return error.FileNotPNG;

    var last_chunk = false;
    const CT = Chunk(@TypeOf(reader));
    while (true) {
        var chunk: CT = undefined;
        const chunk_r = try chunk.Start(reader);

        const tv = chunk.TypeValue();
        if (tv) |v| {
            switch (v) {
                .IHDR => {
                    if (chunk.length_remaining != 13)
                        return error.IHDRChunkInvalid;
                    _ = try chunk_r.readIntBig(u32); // Width
                    _ = try chunk_r.readIntBig(u32); // Height
                    _ = try chunk_r.readIntBig(u8); // BitDepth
                    _ = try chunk_r.readIntBig(u8); // ColorType
                    _ = try chunk_r.readIntBig(u8); // CompressionMethod
                    _ = try chunk_r.readIntBig(u8); // FilterMethod
                    _ = try chunk_r.readIntBig(u8); // InterlaceMethod
                },
                //.IDAT => null,
                .IEND => {
                    if (chunk.length_remaining != 0)
                        return error.IENDChunkInvalid;
                    last_chunk = true;
                },
                else => {
                    while (chunk.length_remaining > 0)
                        _ = try chunk_r.readByte();
                },
            }
        } else {
            while (chunk.length_remaining > 0)
                _ = try chunk_r.readByte();
        }

        try chunk.End();

        std.debug.print(
            "CHUNK: {s}\n\tlen:  {d}\n\tcrc:  {X:0>8}\n\tancl: {}\n\tpriv: {}\n\tresv: {}\n\tcopy: {}\n",
            .{
                toBytes(nativeToBig(u32, chunk.Type)), chunk.Length,   chunk.Crc,
                chunk.bAncillary,                      chunk.bPrivate, chunk.bReserved,
                chunk.bSafeToCopy,
            },
        );

        if (last_chunk) break;
    }
}

// TODO: ReadIDAT
// multiple IDATs may exist; keep reading/expecting them until all pixels resolved,
// and ignore any trailing bytes
// series of IDATs should be considered as a single deflate encoding unit that
// should be decoded as concatenated data, not as separate self-contained deflate
// units; i.e. the main purpose of splitting IDATs is to reduce memory load on
// encoders/decoders by limiting how big the read buffer needs to be to parse piecemeal

// https://evanhahn.com/worlds-smallest-png/
const TestImage = [_]u8{
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x00, 0x00, 0x37, 0x6E, 0xF9,
    0x24,
    0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT
    0x78, 0x01, 0x63, 0x60, 0x00, 0x00, 0x00, 0x02,
    0x00, 0x01, 0x73, 0x75, 0x01, 0x18,
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
    0xAE, 0x42, 0x60, 0x82,
};

test "read png" {
    var fbs = std.io.fixedBufferStream(&TestImage);
    try Read(fbs.reader());
}

// UTIL

pub fn SetColor(self: *PNG, color_type: ColorType, bit_depth: u8) !void {
    assert(bit_depth > 0);
    assert(std.math.isPowerOfTwo(bit_depth));
    switch (color_type) {
        .Greyscale => assert(bit_depth <= 16),
        .IndexedColor => assert(bit_depth <= 8),
        .Truecolor, .GreyscaleAlpha, .TruecolorAlpha => assert(bit_depth == 8 or bit_depth == 16),
    }
    self.ColorType = color_type;
    self.BitDepth = bit_depth;
}

// CHUNK

inline fn ChunkValue(bytes: *const [4]u8) u32 {
    return std.mem.readInt(u32, bytes, .Big);
}

// more: https://www.w3.org/TR/png-3/#11Chunks
pub const ChunkType = enum(u32) {
    IHDR = ChunkValue(&[4]u8{ 'I', 'H', 'D', 'R' }),
    IDAT = ChunkValue(&[4]u8{ 'I', 'D', 'A', 'T' }),
    IEND = ChunkValue(&[4]u8{ 'I', 'E', 'N', 'D' }),
};

pub fn Chunk(comptime ReaderType: type) type {
    return struct {
        const CT = @This();
        pub const ReaderError = error{ChunkDataOverflow} || ReaderType.Error;
        pub const Reader = std.io.Reader(*CT, ReaderError, read);

        Type: u32,
        Length: u32,
        Crc: u32 = 0xFFFFFFFF,
        bAncillary: bool,
        bPrivate: bool,
        bReserved: bool,
        bSafeToCopy: bool,

        crc_data: std.hash.Crc32,

        length_remaining: u32 = 0,
        src_reader: ReaderType,

        /// reads a chunk up until the data segment. user is responsible for
        /// processing the data segment using the reader provided in the return
        /// value, and then should call End to validate the crc.
        /// @r          a png data stream with the cursor expected to be at the
        ///             top of a chunk. the return Reader will wrap this, meaning
        ///             the user's reader will be progressed to the next chunk
        ///             after calling End
        pub fn Start(self: *CT, r: anytype) !Reader {
            self.Length = try r.readIntBig(u32);
            self.length_remaining = self.Length + 4;

            self.Crc = 0xFFFFFFFF;
            self.crc_data = std.hash.Crc32.init();
            self.src_reader = r;
            const self_r: Reader = self.reader();

            self.Type = try self_r.readIntBig(u32);

            self.bAncillary = (self.Type & 0x20000000) > 0;
            self.bPrivate = (self.Type & 0x00200000) > 0;
            self.bReserved = (self.Type & 0x00002000) > 0;
            self.bSafeToCopy = (self.Type & 0x00000020) > 0;

            return self_r;
        }

        /// finalizes a chunk by reading and validating the crc bytes. user is
        /// expected to have initialized the chunk using ChunkStart, and read
        /// through the chunk data using the Chunk.Reader reader
        pub fn End(self: *CT) !void {
            if (self.length_remaining > 0)
                return error.ChunkDataRemaining;

            self.Crc = try self.src_reader.readIntBig(u32);
            const crc_final = self.crc_data.final();

            if (self.Crc != crc_final)
                return error.ChunkCrcMismatch;
        }

        pub fn CurrentCrc(self: *CT) u32 {
            return self.crc_data.crc;
        }

        pub fn TypeValue(self: *const CT) ?ChunkType {
            return std.meta.intToEnum(ChunkType, self.Type) catch null;
        }

        fn read(self: *CT, buf: []u8) ReaderError!usize {
            const amt: u32 = @truncate(try self.src_reader.read(buf));
            if (self.length_remaining < amt) return error.ChunkDataOverflow;

            self.crc_data.update(buf[0..amt]);
            self.length_remaining -= amt;

            return amt;
        }

        fn reader(self: *CT) Reader {
            return .{ .context = self };
        }
    };
}

// CRC
// FIXME: probably just remove this after doing chunk writer; already integrated
// into chunk reader

// https://www.w3.org/TR/png-3/#D-CRCAppendix

const CRCLUT: [256]u32 = crc: {
    @setEvalBranchQuota(256 * 8 * 2);
    var table: [256]u32 = undefined;
    for (0..256) |n| {
        var c: u32 = n;
        for (0..8) |_| c = if ((c ^ 1) > 0) 0xEDB88320 ^ (c >> 1) else c >> 1;
        table[n] = c;
    }
    break :crc table;
};

pub fn UpdateCRC(crc: u32, buf: []const u8) u32 {
    var c = crc;
    for (buf) |b| c = CRCLUT[(c ^ b) & 0xFF] ^ (c >> 8);
    return c;
}

pub fn DoCRC(buf: []const u8) u32 {
    return UpdateCRC(0xFFFFFFFF, buf);
}

/// a writer that calculates the PNG CRC of the bytes written through it
pub fn CRCWriter(comptime WriterType: type) type {
    return struct {
        crc: u32,
        child_stream: WriterType,

        pub const Error = WriterType.Error;
        pub const Writer = std.io.Writer(*Self, Error, write);

        const Self = @This();

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            const amt = try self.child_stream.write(bytes);
            self.crc = UpdateCRC(self.crc, bytes[0..amt]);
            return amt;
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

/// a reader that calculates the PNG CRC of the bytes read through it
pub fn CRCReader(comptime ReaderType: type) type {
    return struct {
        crc: u32,
        child_stream: ReaderType,

        pub const Error = ReaderType.Error;
        pub const Reader = std.io.Reader(*Self, Error, read);

        const Self = @This();

        pub fn read(self: *Self, buf: []u8) Error!usize {
            const amt = try self.child_stream.read(buf);
            self.crc = UpdateCRC(self.crc, buf[0..amt]);
            return amt;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}

pub fn crcWriter(child_stream: anytype) CRCWriter(@TypeOf(child_stream)) {
    return .{ .crc = 0xFFFFFFFF, .child_stream = child_stream };
}

pub fn crcReader(child_stream: anytype) CRCReader(@TypeOf(child_stream)) {
    return .{ .crc = 0xFFFFFFFF, .child_stream = child_stream };
}

// FIXME: finish test impl
//test "CRCWriter" {
//    var crc_stream = crcWriter(std.io.null_writer);
//    const stream = crc_stream.writer();
//
//    const bytes = "yay" ** 100;
//    stream.writeAll(bytes) catch unreachable;
//    try std.testing.expect(crc_stream.crc == 0xFFFFFFFF); // FIXME: figure out actual crc manually
//}

// FIXME: finish test impl
//test "CRCReader" {
//    const bytes = "yay" ** 100;
//    var fbs = std.io.fixedBufferStream(bytes);
//    var crc_stream = crcReader(fbs.reader());
//    const stream = crc_stream.reader();
//
//    //read and discard all bytes
//    while (stream.readByte()) |_| {} else |err| {
//        try std.testing.expect(err == error.EndOfStream);
//    }
//    try std.testing.expect(crc_stream.crc == 0xFFFFFFFF); // FIXME: figure out actual crc manually
//}

// helpers

pub fn WriteGrey8(_: *PNG) void {}
