const std = @import("std");
const assert = std.debug.assert;
const maxInt = std.math.maxInt;

// FIXME: move sprite-, block-, etc. specific stuff to separate files

// GAME TYPEDEFS

pub const BlockFileType = enum(u32) { Model, Sprite, Spline, Texture };

// FIXME: move to Color.zig
pub const COLOR_RGB24 = packed struct(u24) { R: u8, G: u8, B: u8 };
pub const COLOR_RGBA16 = packed struct(u24) { R: u4, G: u4, B: u4, A: u4 };
pub const COLOR_RGBA32 = packed struct(u32) { R: u8, G: u8, B: u8, A: u8 };
pub const COLOR_RGBA5551 = packed struct(u16) { R: u5, G: u5, B: u5, A: u1 };
pub const COLOR_GREY4 = u4; // "grey" is actually white + alpha?
pub const COLOR_GREY8 = u8;

// pixel encoding
// FIXME: false enum, the "format" is a two-part value where the structure and
// bits per pixel are encoded as separate bytes (aka "format" and "alignment"
// in materials).  below is the traditional "block sprites" view on encoding
// textures/sprites, based on observing the block files and inadvertently merging
// both fields as a single encoded value
// NOTE: it may be worthwhile to keep this around in some form as an enumeration
// of the structure/bpp combinations the game supports.  note that in this case
// the values still need to be updated and expanded with new knowledge
// NOTE: also not to be confused with "ColorFormat", which is currently the name
// for the pixel format of uncompressed (loaded) images;  i.e. the format that
// data in the formats below gets turned into
pub const PIXEL_FORMAT = enum(u16) {
    RGBA32 = 0x0003,
    Palette16 = 0x0200,
    Palette256 = 0x0201,
    Greyscale4 = 0x0400,
    Greyscale8 = 0x0401,
};

pub const PixelStructure = enum(u8) {
    // 0 raw/uncompressed BE?
    // 2 palletted
    // 3 grey/alpha?
    // 4 grey/alpha BE?
    // 5 raw/uncompressed?
};

pub const PixelBits = enum(u8) { BPP4 = 0, BPP8 = 1, BPP16 = 2, BPP32 = 3, BPP24 = 7 };

// GAME CONSTANTS

// *anyopaque here refers to c std FILE*
pub const pOpenSpriteBlockFile: **anyopaque = @ptrFromInt(0x4B958C);
pub const pOpenSplineBlockFile: **anyopaque = @ptrFromInt(0x4B9590);
pub const pOpenTextureBlockFile: **anyopaque = @ptrFromInt(0x4B9594);
pub const pOpenModelBlockFile: **anyopaque = @ptrFromInt(0x4B9598);

pub const TextureBuffer: *[1700]u32 = @ptrFromInt(0xE93860); // TODO: texture typedef
pub const TextureBlockCount: *u32 = @ptrFromInt(0xE9823C); // updated in TextureBuffer_Init

// GAME FUNCTIONS

pub const Block_UncompressData: *const fn ([*]u8, [*]u8) callconv(.C) void = @ptrFromInt(0x42D520);
pub const Block_GetLoadedFile: *const fn (BlockFileType) callconv(.C) void = @ptrFromInt(0x42D600);
pub const Block_Read: *const fn (BlockFileType, u32, [*]u8, u32) callconv(.C) void = @ptrFromInt(0x42D640);
pub const Block_Open: *const fn (BlockFileType) callconv(.C) void = @ptrFromInt(0x42D680);
pub const Block_Close: *const fn (BlockFileType) callconv(.C) void = @ptrFromInt(0x42D6F0);
pub const TextureBuffer_Init: *const fn () callconv(.C) void = @ptrFromInt(0x447420);
pub const TextureBuffer_LoadModelTexture: *const fn () callconv(.C) void = @ptrFromInt(0x447490);
pub const TextureBuffer_ClearBufferAfterPtr: *const fn () callconv(.C) void = @ptrFromInt(0x4475D0);

// NOTE: ppPage expects a ptr to raw pixel data in the format indicated by params,
// and will overwrite it with a ptr to a newly allocated Material
pub const Material_CreateFromSpritePage: *const fn (Format: u8, Alignment: u8, Width: i32, Height: i32, WidthMax: i32, HeightMax: i32, ppPage: **anyopaque, ppPalette: *?*i32, UnkBool: i8, UnkFlags: u8) callconv(.C) void = @ptrFromInt(0x445EE0);
pub const Material_Free: *const fn (pMaterial: *anyopaque) callconv(.C) void = @ptrFromInt(0x48EAC0);
pub const Material_FreeEntry: *const fn (pMaterial: *anyopaque) callconv(.C) void = @ptrFromInt(0x48EB00);

// HELPERS

fn PixelColorType(comptime f: PIXEL_FORMAT) type {
    return switch (f) {
        .RGBA32 => COLOR_RGBA32,
        .Palette16, .Palette256 => COLOR_RGBA5551,
        .Greyscale4 => COLOR_GREY4,
        .Greyscale8 => COLOR_GREY8,
    };
}

pub inline fn hConvertBPP(n: u32, comptime Tf: type, comptime Tt: type) Tt {
    comptime {
        const info_f = @typeInfo(Tf);
        const info_t = @typeInfo(Tt);
        assert(info_f.Int.signedness == .unsigned);
        assert(info_t.Int.signedness == .unsigned);
        assert(info_f.Int.bits + info_t.Int.bits <= 32);
    }
    return n * maxInt(Tt) / maxInt(Tf);
}

pub fn PixelFromRGBA(comptime F: PIXEL_FORMAT, pixel: COLOR_RGBA32) PixelColorType(F) {
    return switch (F) {
        .RGBA32 => pixel,
        .Palette16, .Palette256 => COLOR_RGBA5551{
            .R = hConvertBPP(pixel.R, u8, u5),
            .G = hConvertBPP(pixel.G, u8, u5),
            .B = hConvertBPP(pixel.B, u8, u5),
            .A = if (pixel.A > 0xF) 1 else 0,
        },
        .Greyscale4 => hConvertBPP(pixel.R, u8, u4),
        .Greyscale8 => pixel.R,
    };
}

pub fn PixelToRGBA(comptime F: PIXEL_FORMAT, pixel: PixelColorType(F)) COLOR_RGBA32 {
    return switch (F) {
        .RGBA32 => pixel,
        .Palette16, .Palette256 => COLOR_RGBA32{
            .R = hConvertBPP(pixel.R, u5, u8),
            .G = hConvertBPP(pixel.G, u5, u8),
            .B = hConvertBPP(pixel.B, u5, u8),
            .A = 0xFF * pixel.A,
        },
        .Greyscale4 => COLOR_RGBA32{
            .R = hConvertBPP(pixel, u4, u8),
            .G = hConvertBPP(pixel, u4, u8),
            .B = hConvertBPP(pixel, u4, u8),
            .A = 0xFF,
        },
        .Greyscale8 => COLOR_RGBA32{ .R = pixel, .G = pixel, .B = pixel, .A = 0xFF },
    };
}

pub inline fn hExtract4BPP(px: u8, i: usize) u4 {
    return @truncate(0xF & (px >> ((i + 1) % 2) * 4));
}

pub inline fn hInsert4BPP(px: u4, i: usize) u8 {
    return @as(u8, @intCast(px)) << @as(u3, @truncate((i % 2) * 4));
}

// 4bpp alpha -> rgba4444
pub inline fn hA4toRGBA4444(px: u4, fill: u12) u16 {
    return fill | (@as(u16, @intCast(px)) << 12);
}

// grey8+alpha8 -> 4bpp grey
pub inline fn hGA88toG4(px: u16) u4 {
    return @truncate(px >> 4);
}
