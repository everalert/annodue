const GIF = @This();

const std = @import("std");
const assert = std.debug.assert;
const Writer = std.io.Writer;
const Reader = std.io.Reader;
const Allocator = std.mem.Allocator;

// GIF 87a/89a
// NOTE: just implementing enough to read single frame gifs for now
// at the time of writing, the usecase is reading greyscale font glyphs

// References
// https://en.wikipedia.org/wiki/GIF
// https://www.w3.org/Graphics/GIF/spec-gif89a.txt
// https://giflib.sourceforge.net/whatsinagif/bits_and_bytes.html
// https://commandlinefanatic.com/cgi-bin/showarticle.cgi?article=art011
// https://www.fileformat.info/format/gif/egff.htm
// https://github.com/lecram/gifdec
// https://github.com/robert-ancell/pygif
// https://github.com/zigimg/zigimg/blob/master/src/formats/gif.zig
// https://medium.com/@alhuslanr/how-lzw-compression-works-explained-in-plain-english-9b8b520dbc53
// https://patents.google.com/patent/US4558302A/en?oq=4558302 (LZW patent/spec)
// https://www.loc.gov/preservation/digital/formats/fdd/fdd000135.shtml (LZW)
// https://www.loc.gov/preservation/digital/formats/fdd/fdd000133.shtml (GIF89a)
// https://giflib.sourceforge.net/gifstandard/LZW-and-GIF-explained.html
// https://stackoverflow.com/a/69817973

// TODO: remaining tests
// TODO: support for animation (NETSCAPE), as well as forced animation
// TODO: support for transparency
// TODO: support for any other currently skipped block or extension types, and
// review overall implementation for any skipped features or version reqs
// TODO: support for exporting sub-images as separate images or to a tilesheet
// TODO: uncompressed GIF support
// https://en.wikipedia.org/wiki/GIF#Uncompressed_GIF
// TODO: allow user to supply a default color table for use when decoding a gif
// that has no local nor global color tables, and/or the option to supply our own
// TODO: allow user to choose between ignoring or using background color; current
// behaviour ignores it, which seems to be the most common behaviour in other
// viewers. see also: https://stackoverflow.com/a/69817973
// TODO: rethink `ClearCanvas`/`FillBackground` wrt spec
// NOTE: according to spec, background only "meaningful" if global color table
// present. how the background is filled without the presence of the table is
// undefined. see also earlier todo about bg color behaviour
// NOTE: the above notes on background color should also be considered when
// implementing the encoder.
// - main point is a gif decodable according to the spec needs a global color
//   table for the bg color if there are pixels not covered by any sub-image

pub const HEADER_87A = [_]u8{ 'G', 'I', 'F', '8', '7', 'a' };
pub const HEADER_89A = [_]u8{ 'G', 'I', 'F', '8', '9', 'a' };

pub const BlockLabel = enum(u8) {
    ImageDescriptor = 0x2C,
    Extension = 0x21,
    Trailer = 0x3B,
};

pub const ExtensionLabel = enum(u8) {
    Application = 0xFF,
    Comment = 0xFE,
    GraphicControl = 0xF9,
    PlainText = 0x01,
};

pub const DisposalMethod = enum(u3) {
    Unspecified = 0,
    NoDisposal = 1,
    RestoreBG = 2,
    RestorePrev = 3,
    _,
};

// FIXME: move to different file, not gif-specific
pub const RGB = extern struct {
    R: u8,
    G: u8,
    B: u8,

    pub fn ToRGBA(self: *const RGB) RGBA {
        return RGBA{ .R = self.R, .G = self.G, .B = self.B, .A = 0xFF };
    }

    pub fn Black() RGB {
        return .{ .R = 0, .G = 0, .B = 0 };
    }
};

// FIXME: move to different file, not gif-specific
pub const RGBA = extern struct {
    R: u8,
    G: u8,
    B: u8,
    A: u8,

    pub fn ToRGB(self: *const RGB) RGB {
        return RGB{ .R = self.R, .G = self.G, .B = self.B };
    }

    pub fn Black() RGBA {
        return .{ .R = 0, .G = 0, .B = 0, .A = 0 };
    }
};

// TODO: version-based feature enforcement, i.e. erroring if 89a features used on 87a gif
Version: ?enum { @"87a", @"89a" },

// Logical Screen Descriptor
CanvasW: u16,
CanvasH: u16,
PackedField: packed struct(u8) {
    ColorTableSize: u3, // 2^(N+1) colors
    bGlobalColorTableSorted: bool, // by "importance" (usually frequency)
    ColorResolution: u3, // 2^(N+1) bpc in the source image (not the encoded one)
    bGlobalColorTable: bool,
},
BackgroundColorIndex: u8,
PixelAspectRatio: u8, // actual ratio is (N+15)/64 when N!=0

GlobalColorTable: ?[]RGB,

pub const GraphicControl = struct {
    PackedField: packed struct(u8) {
        bTransparentColor: bool,
        bUserInput: bool,
        DisposalMethod: DisposalMethod,
        _: u3, // "reserved"
    },
    DelayTime: u16,
    TransparentColorIndex: u8,
};

pub const ImageDescriptor = struct {
    ImageX: u16,
    ImageY: u16,
    ImageW: u16,
    ImageH: u16,
    PackedField: packed struct {
        ColorTableSize: u3, // same logic as global
        _: u2, // "reserved"
        bSort: bool,
        bInterlace: bool,
        bLocalColorTable: bool,
    },
};

/// simple reading of a GIF data stream with default settings that doesn't require
/// user to manage any part of the decoding process. use this if you just want to
/// get the RGBA output of GIF data.
/// @stream     Reader with the cursor at the top of a GIF data stream
/// @pixels     Writer to output the pixels to
/// @w          image width output
/// @h          image height output
pub fn Read(allocator: Allocator, stream: anytype, pixels: anytype, w: *u16, h: *u16) !void {
    var gif = std.mem.zeroes(GIF);
    try ReadHead(&gif, allocator, stream);
    defer if (gif.GlobalColorTable) |gct| allocator.free(gct);
    try ReadBody(&gif, allocator, stream, pixels);
    w.* = gif.CanvasW;
    h.* = gif.CanvasH;
}

/// reads gif header block (header, logical screen descriptor and global color
/// table) from a data stream. this is done as an extra step so that each image
/// data block can be read separately while using this information as context.
/// some notes:
/// -- caller is responsible for freeing potential allocation for GlobalColorTable
/// -- header may be reused for subsequent gif streams without zeroing; global
///    color table can be shared across streams in this way (see gif89a spec)
/// -- function will free existing GlobalColorTable allocation if necessary
pub fn ReadHead(self: *GIF, allocator: Allocator, reader: anytype) !void {
    var buf: [6]u8 = undefined;
    _ = try reader.read(&buf);
    self.Version = null;
    if (std.mem.eql(u8, &buf, &HEADER_87A))
        self.Version = .@"87a";
    if (std.mem.eql(u8, &buf, &HEADER_89A))
        self.Version = .@"89a";
    if (self.Version == null)
        return error.InvalidHeader;
    std.log.debug("ReadMetadata :: Version = {?s}", .{@tagName(self.Version.?)});

    self.CanvasW = try reader.readIntLittle(u16);
    self.CanvasH = try reader.readIntLittle(u16);
    self.PackedField = @bitCast(try reader.readByte());
    self.BackgroundColorIndex = try reader.readByte();
    self.PixelAspectRatio = try reader.readByte();
    std.log.debug("ReadMetadata :: CanvasW = {d}", .{self.CanvasW});
    std.log.debug("ReadMetadata :: CanvasH = {d}", .{self.CanvasH});
    std.log.debug("ReadMetadata :: PackedField = 0b{b:0>8}", .{@as(u8, @bitCast(self.PackedField))});
    std.log.debug("ReadMetadata ::  bGlobalColorTable = {any}", .{self.PackedField.bGlobalColorTable});
    std.log.debug("ReadMetadata ::  ColorResolution = {d}", .{self.PackedField.ColorResolution});
    std.log.debug("ReadMetadata ::  bSort = {any}", .{self.PackedField.bGlobalColorTableSorted});
    std.log.debug("ReadMetadata ::  ColorTableSize = {d}", .{self.PackedField.ColorTableSize});
    std.log.debug("ReadMetadata :: BackgroundColorIndex = {d}", .{self.BackgroundColorIndex});
    std.log.debug("ReadMetadata :: PixelAspectRatio = {d}", .{self.PixelAspectRatio});

    if (self.CanvasW == 0 or self.CanvasH == 0)
        return error.InvalidCanvasDimensions;

    if (self.PackedField.bGlobalColorTable) {
        if (self.GlobalColorTable) |gct|
            allocator.free(gct);
        const len = @as(usize, 1) << (@as(u4, @intCast(self.PackedField.ColorTableSize)) + 1);
        self.GlobalColorTable = try allocator.alloc(RGB, len);
        var gct_slice = std.mem.sliceAsBytes(self.GlobalColorTable.?);
        std.log.debug("ReadMetadata :: gct len = {d}", .{len});
        std.log.debug("ReadMetadata :: gct_slice.len = {d}", .{gct_slice.len});
        _ = try reader.read(gct_slice);
    }
}

// TODO: option to process multiple image blocks as an animation regardless of
// the presence of the NETSCAPE application extension
// TODO: option to process multiple image blocks as individual images rather than
// animation frames
// TODO: option to process image blocks as part of the main canvas (i.e. how the
// spec says to)??? rather than whatever i'm supposed to do to "normally" process
// the image data while ignoring the canvas thing
pub fn ReadBody(self: *const GIF, allocator: Allocator, reader: anytype, writer: anytype) !void {
    const pre = "ReadBody :: ";
    var sbr_buf: [255]u8 = undefined;
    var sbr = MakeSubBlockReader(reader);
    const sbr_r = sbr.reader();

    var canvas: []RGBA = try allocator.alloc(RGBA, self.CanvasW * self.CanvasH);
    defer allocator.free(canvas);
    var cw = ColorWriter.Init(canvas, self);
    cw.ClearCanvas(); // ignore background color
    //cw.FillBackground(); // TODO: option to use the background color (but default ignore)

    var done = false;
    var prev_block: ?struct { BlockLabel, ?ExtensionLabel } = null;
    while (!done) {
        const block_label = reader.readEnum(BlockLabel, .Little) catch
            return error.InvalidBlockLabel;

        std.log.debug(pre ++ "[BLOCK] {s}", .{@tagName(block_label)});
        switch (block_label) {
            .Trailer => {
                if (prev_block != null) return error.PrematureTrailer;
                try cw.ExportBuffer(writer);
                done = true;
            },
            .ImageDescriptor => {
                // does whole image decoding for one data cycle, i.e. parsing
                // of the image descriptor, local color table and image data
                if (prev_block != null and
                    !(prev_block.?[0] == .Extension and
                    prev_block.?[1] != null and
                    prev_block.?[1].? == .GraphicControl))
                    return error.InvalidImageDescriptorLocation;

                std.log.debug(pre ++ " Parsing Image Descriptor", .{});
                var idsc = std.mem.zeroes(ImageDescriptor);
                idsc.ImageX = try reader.readIntLittle(u16);
                idsc.ImageY = try reader.readIntLittle(u16);
                idsc.ImageW = try reader.readIntLittle(u16);
                idsc.ImageH = try reader.readIntLittle(u16);
                idsc.PackedField = @bitCast(try reader.readByte());
                std.log.debug(pre ++ "  ImageX = {d}", .{idsc.ImageX});
                std.log.debug(pre ++ "  ImageY = {d}", .{idsc.ImageY});
                std.log.debug(pre ++ "  ImageW = {d}", .{idsc.ImageW});
                std.log.debug(pre ++ "  ImageH = {d}", .{idsc.ImageH});
                std.log.debug(pre ++ "  PackedField = 0b{b:0>8}", .{@as(u8, @bitCast(idsc.PackedField))});
                std.log.debug(pre ++ "   bLocalColorTable = {any}", .{idsc.PackedField.bLocalColorTable});
                std.log.debug(pre ++ "   bInterlace = {any}", .{idsc.PackedField.bInterlace});
                std.log.debug(pre ++ "   bSort = {any}", .{idsc.PackedField.bSort});
                std.log.debug(pre ++ "   ColorTableSize = {d}", .{idsc.PackedField.ColorTableSize});

                defer prev_block = null;

                if (idsc.ImageW == 0 or idsc.ImageH == 0)
                    continue;

                var local_color_table: ?[]RGB = null;
                if (idsc.PackedField.bLocalColorTable) {
                    std.log.debug(pre ++ " Parsing Local Color Table", .{});
                    const len = @as(usize, 1) << (@as(u4, @intCast(idsc.PackedField.ColorTableSize)) + 1);
                    local_color_table = try allocator.alloc(RGB, len);
                    _ = try reader.read(std.mem.sliceAsBytes(local_color_table.?));
                }
                defer if (local_color_table) |lct| allocator.free(lct);

                // TODO: add option for "default" color table fallback instead of error
                std.log.debug(pre ++ " Parsing Image Data", .{});
                sbr.reset();
                try cw.StartImage(local_color_table, &idsc);
                var lzw = MakeDecodeLZW(allocator, sbr_r, cw.writer());
                defer lzw.Deinit();
                const lzw_min_code_size = try reader.readByte();
                std.log.debug(pre ++ "  MinCodeSize = {d}", .{lzw_min_code_size});
                defer std.log.debug(pre ++ "  Wrote {d}/{d}px", .{ cw.img_px, cw.img_px_max });
                try lzw.Decode(@intCast(lzw_min_code_size));
                try cw.EndImage();
            },
            .Extension => {
                const extension_label = reader.readEnum(ExtensionLabel, .Little) catch
                    return error.InvalidBlockLabel;

                std.log.debug(pre ++ "[EXTENSION] {s}", .{@tagName(extension_label)});
                switch (extension_label) {
                    .GraphicControl => {
                        if (prev_block != null)
                            return error.InvalidGraphicControlExtensionLocation;

                        var g_ctrl = std.mem.zeroes(GraphicControl);
                        sbr.reset();
                        g_ctrl.PackedField = @bitCast(try sbr_r.readByte());
                        g_ctrl.DelayTime = try sbr_r.readIntLittle(u16);
                        g_ctrl.TransparentColorIndex = try sbr_r.readByte();
                        std.log.debug(pre ++ "  PackedField = 0b{b:0>8}", .{@as(u8, @bitCast(g_ctrl.PackedField))});
                        std.log.debug(pre ++ "   bTransparentColor = {any}", .{g_ctrl.PackedField.bTransparentColor});
                        std.log.debug(pre ++ "   bUserInput = {any}", .{g_ctrl.PackedField.bUserInput});
                        std.log.debug(pre ++ "   DisposalMethod = {d}", .{g_ctrl.PackedField.DisposalMethod});
                        std.log.debug(pre ++ "  DelayTime = {d}", .{g_ctrl.DelayTime});
                        std.log.debug(pre ++ "  TransparentColorIndex = {d}", .{g_ctrl.TransparentColorIndex});

                        prev_block = .{ .Extension, extension_label };
                    },
                    .PlainText => {
                        if (prev_block != null and
                            !(prev_block.?[0] == .Extension and
                            prev_block.?[1] != null and
                            prev_block.?[1].? == .GraphicControl))
                            return error.InvalidPlainTextExtensionLocation;

                        const text_block_size = try reader.readByte();
                        // FIXME: to impl, ignoring for now
                        try reader.skipBytes(text_block_size, .{});
                        sbr.reset();
                        while (try sbr_r.read(&sbr_buf) != 0) continue;

                        prev_block = null;
                    },
                    .Application => {
                        if (prev_block != null)
                            return error.InvalidApplicationExtensionLocation;

                        const app_block_size = try reader.readByte();
                        if (app_block_size != 11)
                            return error.InvalidApplicationExtentionBlockSize;
                        // FIXME: to impl, ignoring for now
                        try reader.skipBytes(app_block_size, .{});
                        sbr.reset();
                        while (try sbr_r.read(&sbr_buf) != 0) continue;

                        prev_block = null;
                    },
                    .Comment => {
                        if (prev_block != null)
                            return error.InvalidCommentExtensionLocation;

                        // FIXME: to impl, ignoring for now
                        sbr.reset();
                        while (try sbr_r.read(&sbr_buf) != 0) continue;

                        prev_block = null;
                    },
                }
            },
        }
    }
}

// FIXME: what is supposed to happen with the background color when no global color
// table is present?  fill black?  fill with color from a sub-image?
// -- according to the spec, if the global color table flag is not set (i.e. there
//    is no global color table), then the background color setting is "meaningless"
// TODO: add interlacing support
// TODO: add transparent pixel support
// TODO: add transparent pixel treatment for background color fill
/// translates a stream of color table indices into actual color output
/// - setup with Init
/// - user responsible for providing output buffer memory
/// - wrap each sub-image with StartImage and EndImage
/// - push table indices to the writer to write pixels to the buffer; any special
///   conditions (e.g. interlaced pixel order) will be dealt with automatically
pub const ColorWriter = struct {
    pub const CWError = error{
        NoColorTable,
        NoImageDef,
        ImageTooManyPixels,
        ImageTooFewPixels,
        InvalidColorIndex,
    };
    pub const CWWriter = std.io.Writer(*ColorWriter, CWError, write);

    const INTERLACE_STAGES = [4]struct { step: usize, start: usize }{
        .{ .step = 8, .start = 0 },
        .{ .step = 8, .start = 4 },
        .{ .step = 4, .start = 2 },
        .{ .step = 2, .start = 1 },
    };

    buffer: []RGBA,
    canvas: struct { w: u16, h: u16 },
    global_ctbl: ?[]const RGB,
    background_color: u8,
    transparent_color: ?u8,

    img: struct { x: u16 = 0, y: u16 = 0, w: u16 = 0, h: u16 = 0 } = .{},
    img_ctbl: ?[]const RGB = null,
    img_interlaced: bool = false,
    img_interlace_thresholds: [4]usize = [_]usize{ 0, 0, 0, 0 },
    img_y: usize = 0,
    img_px: usize = 0,
    img_px_max: usize = 0,
    img_start: usize = 0,
    img_usable: struct { w: u16 = 0, h: u16 = 0 } = .{},
    img_initialized: bool = false,

    pub fn Init(buffer: []RGBA, gif: *const GIF) ColorWriter {
        assert(buffer.len == gif.CanvasW * gif.CanvasH);

        return .{
            .buffer = buffer,
            .canvas = .{ .w = gif.CanvasW, .h = gif.CanvasH },
            .global_ctbl = gif.GlobalColorTable,
            .background_color = gif.BackgroundColorIndex,
            .transparent_color = null, // FIXME: impl
        };
    }

    /// @ctbl   image color table; if null, will fallback to global color table
    pub fn StartImage(self: *ColorWriter, ctbl: ?[]const RGB, img: *const ImageDescriptor) CWError!void {
        assert(!self.img_initialized);

        if (ctbl == null and self.global_ctbl == null)
            return error.NoColorTable;

        self.img_ctbl = ctbl;
        self.img_px = 0;
        self.img_px_max = img.ImageW * img.ImageH;
        self.img = .{ .x = img.ImageX, .y = img.ImageY, .w = img.ImageW, .h = img.ImageH };
        self.img_interlaced = img.PackedField.bInterlace;
        self.img_y = 0;
        self.img_initialized = true;
        self.img_start = img.ImageX + img.ImageY * self.canvas.w;
        self.img_usable = .{ .w = self.canvas.w - img.ImageX, .h = self.canvas.h - img.ImageY };

        var threshold: usize = 0;
        for (INTERLACE_STAGES, 0..) |stage, i| {
            threshold += (self.img.h + stage.start) / stage.step;
            self.img_interlace_thresholds[i] = threshold;
        }
    }

    pub fn EndImage(self: *ColorWriter) CWError!void {
        if (self.img_px < self.img_px_max)
            return error.ImageTooFewPixels;
        if (self.img_px > self.img_px_max)
            return error.ImageTooManyPixels;

        self.img_initialized = false;
    }

    pub fn ClearCanvas(self: *ColorWriter) void {
        @memset(self.buffer, RGBA{ .R = 0, .G = 0, .B = 0, .A = 0 });
    }

    pub fn FillBackground(self: *ColorWriter) void {
        var color = RGBA.Black();
        if (self.global_ctbl != null and self.background_color < self.global_ctbl.?.len)
            color = self.global_ctbl.?[self.background_color].ToRGBA();
        @memset(self.buffer, color);
    }

    /// @w      writer
    pub fn ExportBuffer(self: *const ColorWriter, w: anytype) !void {
        try w.writeAll(@as([*]const u8, @ptrCast(self.buffer))[0 .. self.buffer.len * @sizeOf(RGBA)]);
    }

    pub fn write(self: *ColorWriter, bytes: []const u8) CWError!usize {
        if (self.img_px >= self.img_px_max)
            return error.ImageTooManyPixels;
        assert(self.img_initialized);

        const ctbl = self.img_ctbl orelse self.global_ctbl orelse
            return error.NoColorTable;

        var bytes_processed: usize = 0;
        for (bytes) |b| {
            if (self.img_px >= self.img_px_max)
                return error.ImageTooManyPixels;
            if (ctbl.len <= b)
                return error.InvalidColorIndex;

            const ix = self.img_px % self.img.w;
            const ty = self.img_px / self.img.w;
            self.img_y = if (self.img_interlaced) il: {
                if (ix != 0) break :il self.img_y;
                var prev_threshold: usize = 0;
                for (INTERLACE_STAGES, self.img_interlace_thresholds) |st, th| {
                    if (ty == prev_threshold) break :il st.start;
                    prev_threshold = th;
                    if (ty >= th) continue;
                    break :il self.img_y + st.step;
                }
                unreachable;
            } else self.img_px / self.img.w;
            const iy = self.img_y;

            if (ix < self.img_usable.w and iy < self.img_usable.h) {
                const i = self.img_start + ix + iy * self.canvas.w;
                self.buffer[i] = ctbl[b].ToRGBA();
            }
            self.img_px += 1;
            self.img_initialized = self.img_px < self.img_px_max;
            bytes_processed += 1;
        }
        return bytes_processed;
    }

    pub fn writer(self: *ColorWriter) CWWriter {
        return .{ .context = self };
    }
};

/// a reader wrapper that allows you to read bytes of a series of sub-blocks
/// as though the data bytes were one contiguous block
/// usage/notes:
/// - call reset() immediately before reading a sub-block section
/// - read() returning less than the requested byte count (reader EOF case) means
///   the block terminator was reached and there is no more data; any other
///   reason sub-block data cannot be read will be returned as an error
/// - after reading all the sub-blocks, the backing reader's cursor will be at
///   the byte after the block terminator
pub fn SubBlockReader(comptime ReaderType: type) type {
    return struct {
        const SBR = @This();
        const Error = ReaderType.Error || error{EndOfStream};
        pub const Reader = std.io.Reader(*SBR, Error, read);

        const BACK_BUF_SIZE = 256 * 3;

        backing_reader: ReaderType,
        backing_buffer: [BACK_BUF_SIZE]u8,
        cursor: u16,
        stored: u16,
        terminated: bool,

        pub fn init(backing_reader: ReaderType) SBR {
            return SBR{
                .backing_reader = backing_reader,
                .backing_buffer = std.mem.zeroes([BACK_BUF_SIZE]u8),
                .cursor = 0,
                .stored = 0,
                .terminated = false,
            };
        }

        pub fn reset(self: *SBR) void {
            self.backing_buffer = std.mem.zeroes([BACK_BUF_SIZE]u8);
            self.cursor = 0;
            self.stored = 0;
            self.terminated = false;
        }

        pub fn read(self: *SBR, buffer: []u8) Error!usize {
            var to_read = buffer.len;
            var cursor: usize = 0;
            while (to_read > 0) {
                // accumulate stage
                // written to ensure the block terminator is read from the backing
                // reader in advance of the user reading the last sub-block
                while (!self.terminated and self.stored < 256) {
                    // FIXME: bug - unhandled error case - could reach EOF here
                    var block_size: u8 = try self.backing_reader.readByte();
                    if (block_size == 0) {
                        self.terminated = true;
                        break;
                    }

                    // FIXME: bug - unhandled error case - could reach EOF here
                    // and return fewer bytes than we need, causing a cursor desync
                    var data_end = (self.cursor + self.stored) % BACK_BUF_SIZE;
                    const bytes_to_end = BACK_BUF_SIZE - data_end;
                    if (bytes_to_end < block_size) {
                        _ = try self.backing_reader.read(self.backing_buffer[data_end..BACK_BUF_SIZE]);
                        self.stored += bytes_to_end;
                        block_size -= @intCast(bytes_to_end);
                        data_end = 0;
                    }
                    _ = try self.backing_reader.read(self.backing_buffer[data_end .. data_end + block_size]);
                    self.stored += block_size;
                }

                // consume stage
                while (to_read > 0 and self.stored > 0) {
                    const bytes_readable = @min(self.stored, BACK_BUF_SIZE - self.cursor);
                    const bytes_to_read = @min(to_read, bytes_readable);
                    @memcpy(
                        buffer[cursor .. cursor + bytes_to_read],
                        self.backing_buffer[self.cursor .. self.cursor + bytes_to_read],
                    );
                    cursor += bytes_to_read;
                    to_read -= bytes_to_read;
                    self.stored -= bytes_to_read;
                    self.cursor = (self.cursor + bytes_to_read) % BACK_BUF_SIZE;
                }

                if (self.stored == 0 and self.terminated)
                    break;
            }

            return cursor; // amount of bytes that made it to the output
        }

        pub fn reader(self: *SBR) SBR.Reader {
            return .{ .context = self };
        }
    };
}

pub fn MakeSubBlockReader(BackingReader: anytype) SubBlockReader(@TypeOf(BackingReader)) {
    return SubBlockReader(@TypeOf(BackingReader)).init(BackingReader);
}

// WARN: implementation specific to GIF-style lzw encoding, meaning it has some
// codes with special meaning and uses a variable-length bit size for codes, as
// well as settings specific for GIF. this stuff would need to be removed or
// adjusted for a generalized lzw implementation, see references at top of document.
/// LZW decoder specific to GIF-style LZW. This implementation only deals with
/// translating compressed codes into an uncompressed index stream. The user is
/// responsible for mapping the output to actual color values.
pub fn DecodeLZW(
    comptime ReaderType: type,
    comptime WriterType: type,
) type {
    const ValueType = u8; // max 256 starting codes in GIF
    const CodeType = u12; // max 4096 codes in GIF
    const TableCodeType = u13; // std.meta.Int(.unsigned, @bitSizeOf(CodeType) + 1);
    const MinCodeSizeType = u4; // std.meta.Int(.unsigned, std.math.log2_int(@bitSizeOf(ValueType))+1);
    const CodeSizeType = u4; // std.meta.Int(.unsigned, std.math.log2_int_ceil(@bitSizeOf(TableCodeType)));
    const Endian = std.builtin.Endian.Little; // GIF always uses LE codes?
    //const CodeTableSize = 4096; // meant to inform static buffer size; using allocator for now

    // TODO: assert ValueType is an unsigned int ; std.meta.trait.isUnsignedInt ?
    // TODO: assert ValueType bits are byte-aligned ; @bitSizeOf % 8 == 0
    // TODO: assert CodeType is an unsigned int
    // TODO: assert CodeType bits >= ValueType bits

    const MAX_CODE = std.math.maxInt(CodeType);
    const MAX_CODE_SIZE = @bitSizeOf(CodeType);
    const MIN_STARTING_CODE_SIZE = 2; // GIF
    const MAX_STARTING_CODE_SIZE = 8; // @bitSizeOf(ValueType);

    return struct {
        const LZW = @This();

        const TableItem = struct {
            value: ValueType,
            start: ValueType,
            prefix: ?TableCodeType = null,
        };

        reader: ReaderType,
        writer: WriterType,
        table: std.AutoArrayHashMap(TableCodeType, TableItem),
        table_code_clr: TableCodeType = 0,
        table_code_eoi: TableCodeType = 0,

        pub fn Init(allocator: Allocator, reader: ReaderType, writer: WriterType) LZW {
            return .{
                .reader = reader,
                .writer = writer,
                .table = std.AutoArrayHashMap(TableCodeType, TableItem).init(allocator),
            };
        }

        pub fn Deinit(self: *LZW) void {
            defer self.table.deinit();
        }

        pub fn Decode(self: *LZW, min_code_size: MinCodeSizeType) !void {
            assert(min_code_size >= MIN_STARTING_CODE_SIZE);
            assert(min_code_size <= MAX_STARTING_CODE_SIZE);
            const starting_code_count = @as(TableCodeType, 1) << min_code_size;
            try self.TableReset(starting_code_count);

            var br = std.io.bitReader(Endian, self.reader);
            var bits_read: usize = std.math.maxInt(usize);
            var code_size = @as(CodeSizeType, @intCast(min_code_size)) + 1;
            var code_count_prev = self.table.count();

            var N: TableCodeType = 0; // N = Next (input code)
            var P: TableCodeType = 0; // P = Prev (input code)
            var NC: TableCodeType = self.table_code_eoi + 1; // NC = Next Code (to add to table)
            var NCT = @as(TableCodeType, 1) << code_size; // NCT = Next Code Threshold

            var i: usize = 0;
            while (bits_read > 0) : (i += 1) {
                N = try br.readBits(CodeType, code_size, &bits_read);

                if (bits_read == 0)
                    break; // return error.StopCodeNotFound; ??
                if (bits_read < code_size)
                    return error.InvalidCodeSize;

                defer {
                    P = N;
                    const code_count = self.table.count();
                    defer code_count_prev = code_count;
                    if (code_count > code_count_prev) {
                        NC += 1;
                        if (NC == NCT and code_size < MAX_CODE_SIZE) {
                            code_size += 1;
                            NCT = @as(TableCodeType, 1) << code_size;
                        }
                    }
                }

                std.log.debug(
                    "Decode :: STEP {d: <10}N=#{d: <6}P=#{d: <6}CS={d: <4}NC={d: <6}NCT={d: <6}",
                    .{ i, N, P, code_size, NC, NCT },
                );

                if (N == self.table_code_eoi) {
                    std.log.debug("Decode :: End Of Information", .{});
                    break;
                }

                if (N == self.table_code_clr) {
                    std.log.debug("Decode :: Clearing Table", .{});
                    try self.TableReset(starting_code_count);
                    code_size = @intCast(min_code_size + 1);
                    NC = self.table_code_eoi + 1;
                    NCT = @as(TableCodeType, 1) << (code_size);
                    continue;
                }

                if (N < NC) {
                    //std.log.debug("Decode :: Code Found", .{});

                    try self.ValueEmit(N);
                    //try self.ValueLog(N);

                    if (i == 0 or P == self.table_code_clr or NC > MAX_CODE) continue;

                    if (NC > MAX_CODE) return error.MaxCodeSizeExceeded;
                    assert(self.table.contains(P));
                    const PV = self.table.get(P).?;
                    const NV = self.table.get(N).?;
                    try self.table.put(NC, .{ .value = NV.start, .start = PV.start, .prefix = P });
                } else {
                    //std.log.debug("Decode :: Code Not Found", .{});

                    if (N > NC) return error.InvalidCode; // FIXME: should this continue anyway?
                    if (NC > MAX_CODE) return error.MaxCodeSizeExceeded;
                    assert(self.table.contains(P));
                    const PV = self.table.get(P).?;
                    try self.table.put(NC, .{ .value = PV.start, .start = PV.start, .prefix = P });

                    try self.ValueEmit(NC);
                    //try self.ValueLog(NC);
                }
            }

            //std.log.debug("Decode :: Final Code List", .{});
            //for (0..NC) |c| {
            //    std.log.debug("Decode ::  #{d:0>4}", .{c});
            //    if (c != self.table_code_clr and c != self.table_code_eoi)
            //        try self.ValueLog(@intCast(c));
            //}
        }

        fn TableReset(self: *LZW, starting_code_count: TableCodeType) !void {
            assert(starting_code_count < MAX_CODE - 2);
            self.table_code_clr = starting_code_count;
            self.table_code_eoi = starting_code_count + 1;
            self.table.clearRetainingCapacity();
            for (0..starting_code_count) |i| {
                try self.table.put(@intCast(i), TableItem{
                    .value = @as(ValueType, @intCast(i)),
                    .start = @as(ValueType, @intCast(i)),
                    .prefix = null,
                });
            }
        }

        fn ValueEmit(self: *LZW, code: TableCodeType) !void {
            assert(self.table.contains(code));
            const V = self.table.get(code);

            if (V.?.prefix) |p| try self.ValueEmit(p);

            // FIXME: seems like kind of a hack; if we don't return an error and
            // catch here and just cut off the pixel writing in our `write` (and
            // return the actual number of bytes used), it gets stuck in a loop
            // inside `writeByte`. this is because writeByte calls `writeAll`,
            // which only progresses its while loop based on `write` telling it
            // how many bytes were consumed. however, it also seems like a hack
            // to return the whole number of bytes anyway just because `writeAll`
            // has this behaviour?
            self.writer.writeByte(V.?.value) catch |e| {
                if (e == error.ImageTooManyPixels) return;
                return e;
            };
        }

        fn ValueLog(self: *LZW, code: TableCodeType) !void {
            assert(self.table.contains(code));
            const V = self.table.get(code);

            if (V.?.prefix) |p| try self.ValueLog(p);

            std.log.debug("ValueLog :: {d:0>2}", .{V.?.value});
        }
    };
}

pub fn MakeDecodeLZW(
    allocator: Allocator,
    reader: anytype,
    writer: anytype,
) DecodeLZW(@TypeOf(reader), @TypeOf(writer)) {
    return DecodeLZW(@TypeOf(reader), @TypeOf(writer)).Init(allocator, reader, writer);
}

// FIXME: move to other file or delete; pure util not directly related to gif
pub const LoggingWriter = struct {
    const Error = error{};
    pub const Writer = std.io.Writer(*LoggingWriter, Error, write);

    level: std.log.Level,

    pub fn write(self: *LoggingWriter, bytes: []const u8) Error!usize {
        switch (self.level) {
            .debug => std.log.debug("{any}", .{bytes}),
            else => @panic("not implemented"),
        }
        return bytes.len;
    }

    pub fn writer(self: *LoggingWriter) LoggingWriter.Writer {
        return .{ .context = self };
    }
};

pub fn loggingWriter(level: std.log.Level) LoggingWriter {
    return .{ .level = level };
}

// TESTING

// FIXME: maybe strip all logic from this, and turn the decoding setup into a gif
// helper function, to keep the test as "pure" as possible? i.e. remove the in/out
// streams and make something like `ReadStream`, similar to my QOI api
test "Read GIF" {
    //std.testing.log_level = .debug;
    std.debug.print(" \n", .{});

    const w = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }; // white
    const r = [_]u8{ 0xFF, 0x00, 0x00, 0xFF }; // red
    const b = [_]u8{ 0x00, 0x00, 0xFF, 0xFF }; // blue
    const giflib_expected = (r ** 5 ++ b ** 5) ** 3 ++
        (r ** 3 ++ w ** 4 ++ b ** 3) ** 2 ++
        (b ** 3 ++ w ** 4 ++ r ** 3) ** 2 ++
        (b ** 5 ++ r ** 5) ** 3;

    const p1 = "test_gif/";
    const p2 = p1 ++ "test-pygif/";
    //                              log?  input       expected
    const test_images = [_]struct { bool, []const u8, anyerror![]const u8 }{
        // zig fmt: off
        // https://giflib.sourceforge.net/whatsinagif/bits_and_bytes.html
        .{ false, p1 ++ "giflib-sample.gif",         &giflib_expected },
        // TODO: get through whole test suite
        // pygif test suite
        .{ false, p2 ++ "depth1.gif",                @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "depth2.gif",                @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "depth3.gif",                @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "depth4.gif",                @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "depth5.gif",                @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "depth6.gif",                @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "depth7.gif",                @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "depth8.gif",                @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "four-colors.gif",           @embedFile(p2 ++ "four-colors.rgba") },
        .{ false, p2 ++ "local-color-table.gif",     @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "no-global-color-table.gif", @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "no-data.gif",               @embedFile(p2 ++ "transparent-dot.rgba") },
        .{ false, p2 ++ "zero-width.gif",            error.InvalidCanvasDimensions },
        .{ false, p2 ++ "zero-height.gif",           error.InvalidCanvasDimensions },
        .{ false, p2 ++ "zero-size.gif",             error.InvalidCanvasDimensions },
        // FIXME: image-zero-**: impl error on imagewriter, and recover in gif reader?
        .{ false, p2 ++ "image-zero-width.gif",      @embedFile(p2 ++ "transparent-dot.rgba") },
        .{ false, p2 ++ "image-zero-height.gif",     @embedFile(p2 ++ "transparent-dot.rgba") },
        .{ false, p2 ++ "image-zero-size.gif",       @embedFile(p2 ++ "transparent-dot.rgba") },
        .{ false, p2 ++ "invalid-background.gif",    @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "all-reds.gif",              @embedFile(p2 ++ "all-reds.rgba") },
        .{ false, p2 ++ "all-greens.gif",            @embedFile(p2 ++ "all-greens.rgba") },
        .{ false, p2 ++ "all-blues.gif",             @embedFile(p2 ++ "all-blues.rgba") },
        .{ false, p2 ++ "interlace.gif",             @embedFile(p2 ++ "all-reds.rgba") },
        .{ false, p2 ++ "image-inside-bg.gif",       @embedFile(p2 ++ "image-inside-bg.rgba") },
        .{ false, p2 ++ "image-overlap-bg.gif",      @embedFile(p2 ++ "image-overlap-bg.rgba") },
        .{ false, p2 ++ "image-outside-bg.gif",      @embedFile(p2 ++ "image-outside-bg.rgba") },
        .{ false, p2 ++ "images-combine.gif",        @embedFile(p2 ++ "four-colors.rgba") },
        .{ false, p2 ++ "images-overlap.gif",        @embedFile(p2 ++ "white-dot.rgba") }, 
        .{ false, p2 ++ "high-color.gif",            @embedFile(p2 ++ "high-color.rgba") }, 
        .{ false, p2 ++ "missing-pixels.gif",        @embedFile(p2 ++ "missing-pixels.rgba") },
        .{ false, p2 ++ "extra-pixels.gif",          @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "extra-data.gif",            @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "no-clear.gif",              @embedFile(p2 ++ "white-dot.rgba") },
        // FIXME: no-eoi: impl error on lzw decoder, and recover in gif reader?
        .{ false, p2 ++ "no-eoi.gif",                @embedFile(p2 ++ "white-dot.rgba") },
        .{ false, p2 ++ "no-clear-and-eoi.gif",      @embedFile(p2 ++ "white-hline2.rgba") },
        .{ false, p2 ++ "many-clears.gif",           @embedFile(p2 ++ "checkerboard.rgba") },
        .{ false, p2 ++ "double-clears.gif",         @embedFile(p2 ++ "checkerboard.rgba") },
        .{ false, p2 ++ "invalid-code.gif",          error.InvalidCode }, 
        .{ false, p2 ++ "invalid-colors.gif",        error.InvalidColorIndex }, 
        .{ false, p2 ++ "max-width.gif",             @embedFile(p2 ++ "max-width.rgba") },
        .{ false, p2 ++ "max-height.gif",            @embedFile(p2 ++ "max-height.rgba") },
        // NOTE: unclear what max size is if not 0xFFFF*0xFFFF, or why it should 
        // error; gif spec seems to imply that it's up to the decoder to decide 
        // supported resolution. maybe add max pixels as user option to decoder?
        //.{ true,  pre2 ++ "max-size.gif",              error.Placeholder }, 
        .{ false, p2 ++ "4095-codes-clear.gif",      @embedFile(p2 ++ "random-image.rgba") },
        .{ false, p2 ++ "4095-codes.gif",            @embedFile(p2 ++ "random-image.rgba") },
        .{ false, p2 ++ "255-codes.gif",             @embedFile(p2 ++ "random-image.rgba") },
        .{ false, p2 ++ "large-codes.gif",           @embedFile(p2 ++ "random-image.rgba") },
        // NOTE: max/overflow-codes**: not sure what the purpose of this is. they 
        // all have starting codes that are above the max color table size; this 
        // case should at least cause another error as a matter of course
        //.{ true,  p2 ++ "max-codes.gif",          @embedFile(p2 ++ "random-image.rgba") },
        //.{ true,  p2 ++ "overflow-codes.gif",     error.Placeholder }, 
        //.{ true,  p2 ++ "overflow-codes-max.gif", error.Placeholder }, 
        // NOTE: might skip following for now, seems irrelevant for current 
        // usecase as long as the features are ignored without crashing
        //transparent
        //invalid-transparent
        //disabled-transparent
        //unset-transparent
        //loop-infinite
        //loop-once
        //loop-max
        //loop-buffer
        //loop-buffer_max
        //loop-animexts
        //animation
        //animation-speed
        //animation-no-delays
        //animation-zero-delays
        //dispose-none
        //dispose-keep
        //dispose-restore-background
        //dispose-restore-previous
        //animation-multi-image
        //animation-multi-image-explicit-zero-delay
        //comment
        //large-comment
        //nul-comment
        //invalid-ascii-comment
        //invalid-utf8-comment
        //plain-text
        //xmp-data
        //xmp-data-empty
        //icc-color-profile
        //icc-color-profile-empty
        //unknown-extension
        //unknown-application-extension
        //nul-application-extension
        //gif87a
        //gif87a-animation
        // zig fmt: on
    };

    inline for (test_images) |ti| {
        const log = ti[0];
        const log_old = std.testing.log_level;
        defer std.testing.log_level = log_old;
        if (log) std.testing.log_level = .debug;

        const file = ti[1];
        const expected = ti[2];
        std.log.debug("Reading: {s}", .{file});

        var in = std.io.fixedBufferStream(@embedFile(file));
        const in_r = in.reader();

        var out = std.ArrayList(u8).init(std.testing.allocator);
        defer out.deinit();
        const out_w = out.writer();

        var width: u16 = undefined;
        var height: u16 = undefined;
        const err = Read(std.testing.allocator, in_r, out_w, &width, &height);

        if (expected) |expected_slice| {
            try std.testing.expectEqualSlices(u8, expected_slice, out.items);
        } else |expected_err| {
            try std.testing.expectError(expected_err, err);
        }
    }
}

// FIXME: add test cases for malformed input data
//  - EOF reached in the middle of a sub-block
//  - EOF reached when expecting a block size or block terminator byte
// FIXME: add test case for checking the backing reader does not advance past
// the byte after the block terminator when over-reading the sub-block reader,
// preferably something more discrete than the existing indirect test

test "SubBlockReader" {
    //std.testing.log_level = .debug;
    std.debug.print(" \n", .{});

    const data = [_]u8{
        0x04, 0x01, 0x02, 0x03, 0x04, 0x04, 0x05, 0x06, 0x07, 0x08, 0x00,
        0x04, 0x09, 0x0A, 0x0B, 0x0C, 0x04, 0x0D, 0x0E, 0x0F, 0x10, 0x00,
    };
    const data_expected1 = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
    const data_expected3 = [_]u8{ 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };

    var data_fbs = std.io.fixedBufferStream(&data);
    var sbr = MakeSubBlockReader(data_fbs.reader());
    const sbr_r = sbr.reader();
    var buf: [8]u8 = undefined;

    // data correctness across multiple blocks
    const read_cnt1 = try sbr_r.readAll(&buf);
    try std.testing.expect(read_cnt1 == 8);
    try std.testing.expectEqualSlices(u8, &buf, &data_expected1);

    // already terminated returns/does nothing
    const read_cnt2 = try sbr_r.readAll(&buf);
    try std.testing.expect(read_cnt2 == 0);

    // reset allows the second sub-block series to be read, indirectly confirming
    // that the backing reader did not advance during the "already terminated" test
    sbr.reset();
    const read_cnt3 = try sbr_r.readAll(&buf);
    try std.testing.expect(read_cnt3 == 8);
    try std.testing.expectEqualSlices(u8, &buf, &data_expected3);
}

// FIXME: add test cases for InvalidCodeSize, StopCodeNotFound, MaxCodeSizeExceeded
// FIXME: add test case for images that fill the whole code table

test "LZW Decompress" {
    //std.testing.log_level = .debug;
    std.debug.print(" \n", .{});

    const w = [_]u8{0x00}; // white
    const r = [_]u8{0x01}; // red
    const b = [_]u8{0x02}; // blue

    // image data portion of sample image from:
    // https://giflib.sourceforge.net/whatsinagif/bits_and_bytes.html
    const input = [_]u8{
        0x8C, 0x2D, 0x99, 0x87, 0x2A, 0x1C, 0xDC, 0x33, 0xA0, 0x02, 0x75, 0xEC,
        0x95, 0xFA, 0xA8, 0xDE, 0x60, 0x8C, 0x04, 0x91, 0x4C, 0x01,
    };
    const expected = (r ** 5 ++ b ** 5) ** 3 ++
        (r ** 3 ++ w ** 4 ++ b ** 3) ** 2 ++
        (b ** 3 ++ w ** 4 ++ r ** 3) ** 2 ++
        (b ** 5 ++ r ** 5) ** 3;

    var output: [100]u8 = undefined;
    var fbsi = std.io.fixedBufferStream(&input);
    var fbso = std.io.fixedBufferStream(&output);

    var lzw = MakeDecodeLZW(std.testing.allocator, fbsi.reader(), fbso.writer());
    defer lzw.Deinit();
    try lzw.Decode(2);

    try std.testing.expectEqualSlices(u8, &expected, &output);
}
