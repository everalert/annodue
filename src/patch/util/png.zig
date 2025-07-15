const PNG = @This();

const std = @import("std");
const zlib = std.compress.zlib;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const LinearFifo = std.fifo.LinearFifo;
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

pub fn Read(alloc: Allocator, reader: anytype) !void {
    const CT = Chunk(@TypeOf(reader));

    // FIXME: this would work better in zig 0.13, because zlib decompress is a reader-writer
    // CT.Reader -> FIFO -> zlib decompressor -> decompressed output
    // - renew fifo writer each IDAT block
    // - main point of this is to decouple the IDAT block from the zlib
    //   decompressor so that multiple chunks can be used on it
    var data_buf: ArrayList(u8) = undefined;
    var data_buf_initialized = false;
    defer if (data_buf_initialized) data_buf.deinit();
    const data_buf_w = data_buf.writer();
    var data_fifo_buf: []u8 = try alloc.alloc(u8, 256);
    defer alloc.free(data_fifo_buf);
    var data_fifo = LinearFifo(u8, .Slice).init(data_fifo_buf);
    defer data_fifo.deinit();
    var data_zlib_initialized = false;
    var data_zlib: zlib.DecompressStream(@TypeOf(data_fifo.reader())) = undefined;
    defer if (data_zlib_initialized) data_zlib.deinit();

    const signature: [8]u8 = sig: {
        var signature: [8]u8 = undefined;
        _ = try reader.read(&signature);
        break :sig signature;
    };
    if (!std.mem.eql(u8, &signature, &Signature)) return error.SignatureInvalid;

    var IHDR_width: u32 = 0xFFFFFFFF;
    var IHDR_height: u32 = 0xFFFFFFFF;
    var IHDR_bit_depth: u8 = 0xFF;
    var IHDR_color_type: u8 = 0xFF;
    var IHDR_compression_method: u8 = 0xFF;
    var IHDR_filter_method: u8 = 0xFF;
    var IHDR_interlace_method: u8 = 0xFF;
    var data_scanline_bytes: u32 = 0;
    var data_image_bytes: u32 = 0;

    var prev_chunk_type: u32 = 0;
    var IHDR_seen = false;
    var IDAT_seen = false;
    var IDAT_done = false;
    var IEND_seen = false;
    while (true) {
        var chunk: CT = undefined;
        const chunk_r = try chunk.Start(reader);

        std.debug.print("\nCHUNK: {s}\n", .{toBytes(nativeToBig(u32, chunk.Type))});

        if (chunk.TypeValue()) |v| {
            switch (v) {
                .IHDR => {
                    defer IHDR_seen = true;
                    if (prev_chunk_type != 0)
                        return error.IHDRChunkNotFirst;
                    if (chunk.length_remaining != 13)
                        return error.IHDRChunkInvalidLength;

                    IHDR_width = try chunk_r.readIntBig(u32); // Width
                    IHDR_height = try chunk_r.readIntBig(u32); // Height
                    IHDR_bit_depth = try chunk_r.readIntBig(u8); // BitDepth
                    IHDR_color_type = try chunk_r.readIntBig(u8); // ColorType
                    IHDR_compression_method = try chunk_r.readIntBig(u8); // CompressionMethod
                    IHDR_filter_method = try chunk_r.readIntBig(u8); // FilterMethod
                    IHDR_interlace_method = try chunk_r.readIntBig(u8); // InterlaceMethod

                    if (IHDR_color_type != 0)
                        return error.UnsupportedColorType;
                    if (IHDR_compression_method != 0)
                        return error.UnsupportedCompressionMethod;
                    if (IHDR_filter_method != 0)
                        return error.UnsupportedFilterMethod;
                    if (IHDR_interlace_method != 0)
                        return error.UnsupportedInterlaceMethod;

                    // filter type (1b) + bits needed for pixels in row, padded to next byte
                    data_scanline_bytes = (IHDR_width * IHDR_bit_depth + 7) / 8 + 1;
                    data_image_bytes = data_scanline_bytes * IHDR_height;
                    data_buf = try ArrayList(u8).initCapacity(alloc, data_image_bytes);
                    data_buf_initialized = true;
                },
                .IDAT => {
                    defer IDAT_seen = true;
                    if (IDAT_seen and prev_chunk_type != chunk.Type)
                        return error.IDATChunkNotConsecutive;

                    while (chunk.length_remaining > 0) {
                        if (IDAT_done) {
                            try chunk.ExhaustData();
                            break;
                        }
                        const count_w = try chunk_r.read(data_fifo.writableSlice(0));
                        data_fifo.update(count_w);

                        while (data_fifo.readableLength() >= 4) {
                            if (!data_zlib_initialized) {
                                data_zlib_initialized = true;
                                data_zlib = try zlib.decompressStream(alloc, data_fifo.reader());
                            }
                            const data_zlib_r = data_zlib.reader();

                            if (data_buf.items.len == data_image_bytes) {
                                _ = data_zlib_r.readByte() catch |e|
                                    if (e != error.EndOfStream) return e;
                                IDAT_done = true;
                                try chunk.ExhaustData();
                                break;
                            }

                            const value = try data_zlib_r.readByte();
                            try data_buf_w.writeByte(value);
                        }
                    }
                },
                .IEND => {
                    defer IEND_seen = true;
                    if (chunk.length_remaining != 0)
                        return error.IENDChunkInvalidLength;
                },
            }
        } else try chunk.ExhaustData();

        try chunk.End();

        std.debug.print(
            "\tlen:  {d}\n\tcrc:  {X:0>8}\n\tancl: {}\n\tpriv: {}\n\tresv: {}\n\tcopy: {}\n",
            .{ chunk.Length, chunk.Crc, chunk.bAncillary, chunk.bPrivate, chunk.bReserved, chunk.bSafeToCopy },
        );

        prev_chunk_type = chunk.Type;
        if (IEND_seen) break;
    }

    std.debug.print(
        "\nwidth:      {d}\nheight:     {d}\nbit depth:  {d}\ncolor type: {d}\n",
        .{ IHDR_width, IHDR_height, IHDR_bit_depth, IHDR_color_type },
    );

    std.debug.print("\ndata_buf: {any}\n", .{data_buf.items});
}

// TODO: ReadIDAT
// multiple IDATs may exist; keep reading/expecting them until all pixels resolved,
// and ignore any trailing bytes
// series of IDATs should be considered as a single deflate encoding unit that
// should be decoded as concatenated data, not as separate self-contained deflate
// units; i.e. the main purpose of splitting IDATs is to reduce memory load on
// encoders/decoders by limiting how big the read buffer needs to be to parse piecemeal

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
        /// expected to have initialized the chunk using Start, and read through
        /// the chunk data using the provided Reader. if the data needs to be
        /// skipped for any reason, use ExhaustData
        pub fn End(self: *CT) !void {
            if (self.length_remaining > 0)
                return error.ChunkDataRemaining;

            self.Crc = try self.src_reader.readIntBig(u32);
            const crc_final = self.crc_data.final();

            if (self.Crc != crc_final)
                return error.ChunkCrcMismatch;
        }

        /// progress the reader through the data segment bytes without doing
        /// anything with the data
        pub fn ExhaustData(self: *CT) !void {
            const r = self.reader();
            while (self.length_remaining > 0)
                _ = try r.readByte();
        }

        pub fn CurrentCrc(self: *CT) u32 {
            return self.crc_data.crc;
        }

        pub fn TypeValue(self: *const CT) ?ChunkType {
            return std.meta.intToEnum(ChunkType, self.Type) catch null;
        }

        fn read(self: *CT, buf: []u8) ReaderError!usize {
            const to_read: u32 = @min(self.length_remaining, buf.len);
            if (to_read == 0) return 0;

            const amt: u32 = @truncate(try self.src_reader.read(buf[0..to_read]));
            self.crc_data.update(buf[0..amt]);
            self.length_remaining -= amt;

            return amt;
        }

        fn reader(self: *CT) Reader {
            return .{ .context = self };
        }
    };
}

// HELPERS

pub fn WriteGrey8(_: *PNG) void {}

// TESTING

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
    try Read(std.testing.allocator, fbs.reader());
}
