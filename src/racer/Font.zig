const std = @import("std");

pub const COLOR_GREY4 = @import("Asset.zig").COLOR_GREY4;

// GAME TYPEDEFS

pub const FONT = extern struct {
    _00: i32,
    _04_page_num: i32,
    _08_page_list: [16]?*anyopaque,
    __pad1: u32, // NOTE: padding, technically length of 0x08 array unknown
    _4C_line_height: i16,
    __pad2: i16,
    __pad3: i32,
    __pad4: i32,
    __pad5: i16,
    _5A_char_min: u8,
    _5B_char_max: u8,
    _5C_glyphs: ?[*]GLYPH,
    _60_glyphs_ext: ?[*]GLYPH,
    __pad6: i32,
};

pub const GLYPH = extern struct {
    PageID: i16,
    Advance: i16, // horizontal advance
    OffY: i16, // UP=POS, DN=NEG;  yes, Y is first for offset
    OffX: i16, // LF=POS, RT=NEG
    TexX: i16,
    TexY: i16,
    TexW: i16,
    TexH: i16,
};

// FIXME: move to TextFormat.zig
// aka GLYPH_SWITCH
// used to redirect characters to use another character's glyph
// possibly also related to rendering diacritics
pub const GLYPH_MAP = extern struct {
    _00_glyph1: u8, // FIXME: naming: "glyph_extended" or similar
    _01_glyph2: u8, // FIXME: naming: "glyph"; refers to main glyph set
};

// GAME CONSTANTS

// each page = 64x128 Greyscale4 (format 3 alignment 0)
pub const aFontRawPageData: *[5][0x1000]u8 = @ptrFromInt(0x4B9620); // COLOR_GREY4

// NOTE: named for font def correspondence, not old hd font order
// aFontGlyphs0 overlaps aFontGlyphs0Ext, but length correct according to defs
pub const aFontGlyphs0: *[62]GLYPH = @ptrFromInt(0x4BE620);
pub const aFontGlyphs0Ext: *[15]GLYPH = @ptrFromInt(0x4BE9F0);
pub const aFontGlyphs1: *[27]GLYPH = @ptrFromInt(0x4BEAE0);
pub const aFontGlyphs2: *[27]GLYPH = @ptrFromInt(0x4BEC90);
pub const aFontGlyphs3: *[62]GLYPH = @ptrFromInt(0x4BEE40);
pub const aFontGlyphs3Ext: *[15]GLYPH = @ptrFromInt(0x4BF220);
pub const aFontGlyphs4: *[62]GLYPH = @ptrFromInt(0x4BF310);
pub const aFontGlyphs4Ext: *[15]GLYPH = @ptrFromInt(0x4BF6F0);

pub const aFontDef: *[5]FONT = @ptrFromInt(0x4BF7E0);

// FIXME: move to TextFormat.zig
pub const aFontExtGlyphMapVal: *[36]GLYPH_MAP = @ptrFromInt(0x4BFA10);
pub const aFontExtGlyphMapKey: *[106]u8 = @ptrFromInt(0x4BFA58); // index 0 = ascii 150

// texture coordinates get scaled by these values to convert font page texture
// coordinates to UVs (remap texture size to 0..1) in fn_42D990 @ 0x42DBEE
// instruction locations: 42DBEE, 42DBF6
pub const gFontPageUnitScaleX: *const f32 = @ptrFromInt(0x4AC644); // default 0x0000803C (1/64)
// instruction locations: 42DBFE, 42DC06
pub const gFontPageUnitScaleY: *const f32 = @ptrFromInt(0x4AC648); // default 0x0000003C (1/128)

// factors to get screen multiple of 320x240, used only in fn_42D990
pub const gScreenUnitScaleX: *const f64 = @ptrFromInt(0x4AC628); // default 0x9A9999999999693F (1/320)
pub const gScreenUnitScaleY: *const f64 = @ptrFromInt(0x4AC630); // default 0x111111111111713F (1/240)

// FIXME: move to rendering-related file, just here for convenience during font work
// actual window canvas size
pub const gScreenW: *i32 = @ptrFromInt(0xEC86C4);
pub const gScreenH: *i32 = @ptrFromInt(0xEC85E8);

// TODO: use vec4i32 type
// clip region in screen coordinates in order: x1, y1, x2, y2
pub const gCurrentClipRegion: *[4]i32 = @ptrFromInt(0xE99750);
pub const gbCurrentHiRes: *i32 = @ptrFromInt(0x50C0AC); // TODO: confirm type; probably BOOL(32), but i8 in ida

// GAME FUNCTIONS

// FIXME: re-evaluate which of these needs to move; proximity in binary suggests
// they are not all from the fonts lib
pub const fnFontSubstringWidth: *const fn (str: ?[*:0]const u8, fid: i32, s: i32, e: i32) callconv(.C) void =
    @ptrFromInt(0x418680);
pub const fnFontInit: *const fn () callconv(.C) void =
    @ptrFromInt(0x42D720);
pub const fnFontSetCurrent: *const fn (fid: i16) callconv(.C) void =
    @ptrFromInt(0x42D8D0);
pub const fnFontSetCurrent2: *const fn (fid: i16) callconv(.C) void =
    @ptrFromInt(0x42D900);
pub const fnFontStringWidthById: *const fn (str: ?[*:0]const u8, fid: i32) callconv(.C) void =
    @ptrFromInt(0x42DE10);
pub const fnFontStringWidth: *const fn (str: ?[*:0]const u8, f: ?*FONT) callconv(.C) void =
    @ptrFromInt(0x42DE30);
pub const fnFontStringHeight: *const fn (str: ?[*:0]const u8, f: ?*FONT) callconv(.C) void =
    @ptrFromInt(0x42DF70);
pub const fnFontGlyphSize: *const fn (c: u8, f: ?*FONT, out_w: ?*i32, out_h: ?*i32) callconv(.C) void =
    @ptrFromInt(0x42E0E0);

// HELPERS

// ..
