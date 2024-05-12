/// Screen-space sprite drawing

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

// GAME CONSTANTS

// TODO: maybe change 'index' to 'count', since it's the first uninitialized index
pub const QUAD_INITIALIZED_INDEX_ADDR: usize = 0x4B91B8;
pub const QUAD_INITIALIZED_INDEX: *u16 = @ptrFromInt(QUAD_INITIALIZED_INDEX_ADDR);
pub const QUAD_STAT_BAR_INDEX_ADDR: usize = 0x50C928;
pub const QUAD_STAT_BAR_INDEX: *u16 = @ptrFromInt(QUAD_STAT_BAR_INDEX_ADDR);

// HELPER FUNCTIONS

pub fn InitNewQuad(spr: u32) !u16 {
    if (QUAD_INITIALIZED_INDEX.* >= 400) return error.QueueFull;

    const index = QUAD_INITIALIZED_INDEX.*;
    swrQuad_InitQuad(index, spr);
    return index;
}
