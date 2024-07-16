/// Screen-space sprite drawing
const std = @import("std");
const BOOL = std.os.windows.BOOL;

// GAME FUNCTIONS

pub const swrQuad_InitQuad: *fn (i: u16, spr: u32) callconv(.C) void = @ptrFromInt(0x4282F0);
pub const swrQuad_LoadSprite: *fn (i: u32) callconv(.C) u32 = @ptrFromInt(0x446FB0);
pub const swrQuad_LoadTga: *fn (filename: [*:0]const u8, i: u32) callconv(.C) u32 = @ptrFromInt(0x4114D0);
pub const swrQuad_SetActive: *fn (i: u16, on: u32) callconv(.C) void = @ptrFromInt(0x4285D0);
pub const swrQuad_SetFlags: *fn (i: u16, flags: u32) callconv(.C) void = @ptrFromInt(0x4287E0);
pub const swrQuad_ClearFlagsExcept: *fn (i: u16, flags: u32) callconv(.C) void = @ptrFromInt(0x4287E0);
pub const swrQuad_SetPosition: *fn (i: u16, x: i16, y: i16) callconv(.C) void = @ptrFromInt(0x428660);
pub const swrQuad_SetScale: *fn (i: u16, w: f32, h: f32) callconv(.C) void = @ptrFromInt(0x4286F0);
pub const swrQuad_SetColor: *fn (i: u16, r: u8, g: u8, b: u8, a: u8) callconv(.C) void = @ptrFromInt(0x428740);
pub const DrawSprite: *fn (sprite: ?*anyopaque, x: i16, y: i16, w: f32, h: f32, ang: f32, unk7: i16, unk8: i16, unk9: i32, r: u8, g: u8, b: u8, a: u8) callconv(.C) void = @ptrFromInt(0x44F670);
pub const DrawQuad: *fn (quad: *Quad, flags: i32, px_size_x: f32, px_size_y: f32) callconv(.C) void = @ptrFromInt(0x428030);
pub const ResetMaterial: *fn () callconv(.C) void = @ptrFromInt(0x44F5F0); // FIXME: move? also for text etc.

// GAME CONSTANTS

// TODO: maybe change 'index' to 'count', since it's the first uninitialized index
pub const QUAD_INITIALIZED_INDEX_ADDR: usize = 0x4B91B8;
pub const QUAD_INITIALIZED_INDEX: *u16 = @ptrFromInt(QUAD_INITIALIZED_INDEX_ADDR);
pub const QUAD_STAT_BAR_INDEX_ADDR: usize = 0x50C928;
pub const QUAD_STAT_BAR_INDEX: *u16 = @ptrFromInt(QUAD_STAT_BAR_INDEX_ADDR);
pub const QUAD_SKIP_RENDERING_ADDR: usize = 0x50C058;
pub const QUAD_SKIP_RENDERING: *BOOL = @ptrFromInt(QUAD_SKIP_RENDERING_ADDR);

// GAME TYPEDEFS

// size=0x20
const Quad = extern struct {
    PosX: i16,
    PosY: i16,
    _unk_04_06: [2]u8,
    _unk_06_08: [2]u8,
    ScaleX: f32,
    ScaleY: f32,
    _unk_10_14: [4]u8,
    Flags: i32, // TODO: enum
    Color: u32, // TODO: color_u8 typedef
    pSprite: *anyopaque, // TODO: typedef
};

// 0x14 flags
//1<<00	?? set on during quad init
//1<<01
//1<<02	flip horizontal
//1<<03	flip vertical (TGAs loaded are rendered flipped vertically by default?)
//1<<04
//1<<05	visible
//1<<06
//1<<07
//1<<08
//1<<09	?? seen in fn_464630
//1<<10
//1<<11	?? seen in fn_464630, fn_408220
//1<<12	?? seen in fn_464630
//1<<13	enable world-space clipping; i.e. draw in 3d space, not in front of everything
//1<<14	?? on for lens flares, see fn_464010;
//1<<15	?? 'sprite has transparency'? .. leaving off has the effect of a black faded border on color mask sprites, as though the mask is being applied to the black part of the image rather than on the color you give it; on for lens flares, see fn_464010; seen in fn_458250, fn_464630
//1<<16	high-res mode (320x240->640x480)?  on for lens flares, see fn_464010; on for "STAR" title text, see fn_435240
//1<<17
//1<<18
//1<<19	?? ref in fn_4584A0, used on track select icons (both flags and the plain one)
//1<<20
//1<<21
//1<<22
//1<<23
//1<<24
//1<<25
//1<<26
//1<<27
//1<<28
//1<<29
//1<<30
//1<<31

// HELPER FUNCTIONS

pub fn InitNewQuad(spr: u32) !u16 {
    if (QUAD_INITIALIZED_INDEX.* >= 400) return error.QueueFull;

    const index = QUAD_INITIALIZED_INDEX.*;
    swrQuad_InitQuad(index, spr);
    return index;
}
