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
const ColorType = enum(u8) {
    Greyscale = 0,
    Truecolor = 2,
    IndexedColor = 3,
    GreyscaleAlpha = 4,
    TruecolorAlpha = 6,
};

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

// TODO: api where we can get the metadata back before actually decoding the image
// data, to allow the caller to setup for things like extracting the image palette
// before the data, displaying adam7 progressive images, etc.

pub fn Read(gpa: Allocator, reader: anytype) !void {
    const CT = Chunk(@TypeOf(reader));

    // FIXME: this would work better in zig 0.13, because zlib decompress is a reader-writer
    // CT.Reader -> FIFO -> zlib decompressor -> decompressed output
    // - renew fifo writer each IDAT block
    // - main point of this is to decouple the IDAT block from the zlib
    //   decompressor so that multiple chunks can be used on it
    var data_buf = ArrayList(u8).init(gpa);
    defer data_buf.deinit();
    const data_buf_w = data_buf.writer();
    var data_fifo_buf: []u8 = try gpa.alloc(u8, 256);
    defer gpa.free(data_fifo_buf);
    var data_fifo = LinearFifo(u8, .Slice).init(data_fifo_buf);
    defer data_fifo.deinit();
    // lazy init this because the backing reader needs to already have the zlib
    // header in the data stream before init
    var data_zlib_initialized = false;
    var data_zlib: zlib.DecompressStream(@TypeOf(data_fifo.reader())) = undefined;
    defer if (data_zlib_initialized) data_zlib.deinit();

    var filter_buf = ArrayList(u8).init(gpa);
    defer filter_buf.deinit();
    const filter_buf_w = filter_buf.writer();

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

                    if (IHDR_bit_depth > 8)
                        return error.UnsupportedBitDepth;
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
                                data_zlib = try zlib.decompressStream(gpa, data_fifo.reader());
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

    if (data_buf.items.len != data_image_bytes)
        return error.InvalidCompressedData;

    // padding removal for output stream
    const line_bits: usize = IHDR_width * IHDR_bit_depth;
    var line_sh_r: u3 = 0;
    var line_sh_l: u3 = 0;
    var line_mask: u8 = 0x00;
    var recon_next: u8 = 0;
    // line segmenting
    var i_prev: usize = 0;
    var i_this: usize = 0;
    var i_next: usize = 0;
    // do the thing
    for (0..IHDR_height) |i| {
        i_this = i_next;
        i_next = data_scanline_bytes * (i + 1);
        defer i_this = i_next;
        defer i_prev = i_this;

        const row: []const u8 = data_buf.items[i_this..i_next];
        var row_fbs = std.io.fixedBufferStream(row);
        const row_fbs_r = row_fbs.reader();

        const filter_type = try row_fbs_r.readByte();
        var row_bits_left: usize = line_bits;
        while (row_fbs_r.readByte() catch null) |b| {
            // more: https://www.w3.org/TR/png-3/#9-table91
            const recon: u8 = switch (filter_type) {
                0 => b,
                else => return error.UnsupportedFilterType,
            };

            const recon_this: u8 = recon_next | (recon >> line_sh_r);
            recon_next = (recon << line_sh_l) & line_mask;

            if (row_bits_left < 8) {
                const total_excess = row_bits_left + line_sh_r;
                line_sh_r +%= @intCast(row_bits_left);
                line_sh_l -%= @intCast(row_bits_left);
                line_mask = ~(@as(u8, 0xFF) >> line_sh_r);
                if (total_excess >= 8) {
                    try filter_buf_w.writeByte(recon_this);
                    recon_next = recon_next & line_mask;
                } else {
                    recon_next = recon_this & line_mask;
                }
                continue;
            }
            row_bits_left -= 8;
            try filter_buf_w.writeByte(recon_this);
        }
    }
    // some left over
    if (line_sh_r > 0) try filter_buf_w.writeByte(recon_next);

    std.debug.print(
        "\nwidth:      {d}\nheight:     {d}\nbit depth:  {d}\ncolor type: {d}\n",
        .{ IHDR_width, IHDR_height, IHDR_bit_depth, IHDR_color_type },
    );

    std.debug.print(
        "\ndata_buf:   {any}\nfilter_buf: {any}\n",
        .{ data_buf.items, filter_buf.items },
    );
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
// more: https://www.w3.org/TR/png-3/#bib-png-extensions
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

const test_images = [_][]const u8{
    // https://evanhahn.com/worlds-smallest-png/
    "test_png/smallest.png",

    // TODO: remaining suite files (see folder/website)
    // http://www.schaik.com/pngsuite/pngsuite.html
    "test_png/suite/basn0g01.png",
    "test_png/suite/basn0g02.png",
    "test_png/suite/basn0g04.png",
    //"test_png/suite/basn0g08.png", // TODO: filter type/s
    //"test_png/suite/basn0g16.png", // TODO: 16-bit
};

test "read png" {
    inline for (test_images) |ti| {
        var fbs = std.io.fixedBufferStream(@embedFile(ti));
        try Read(std.testing.allocator, fbs.reader());
    }
}
