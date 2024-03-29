pub const Self = @This();

// Text

pub const swrText_CreateEntry: *fn (x: u16, y: u16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8, font: i32, entry2: u32) callconv(.C) void = @ptrFromInt(0x4503E0);

pub const swrText_CreateEntry1: *fn (x: u16, y: u16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x450530);

pub const swrText_CreateEntry2: *fn (x: u16, y: u16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x4505C0);

// Quads

pub const swrQuad_InitQuad: *fn (i: u16, spr: u32) callconv(.C) void = @ptrFromInt(0x4282F0);

pub const swrQuad_LoadSprite: *fn (i: u32) callconv(.C) u32 = @ptrFromInt(0x446FB0);

pub const swrQuad_LoadTga: *fn (filename: [*:0]const u8, i: u32) callconv(.C) u32 = @ptrFromInt(0x4114D0);

pub const swrQuad_SetActive: *fn (i: u16, on: u32) callconv(.C) void = @ptrFromInt(0x4285D0);

pub const swrQuad_SetFlags: *fn (i: u16, flags: u32) callconv(.C) void = @ptrFromInt(0x4287E0);

pub const swrQuad_ClearFlagsExcept: *fn (i: u16, flags: u32) callconv(.C) void = @ptrFromInt(0x4287E0);

pub const swrQuad_SetPosition: *fn (i: u16, x: u16, y: u16) callconv(.C) void = @ptrFromInt(0x428660);

pub const swrQuad_SetScale: *fn (i: u16, w: f32, h: f32) callconv(.C) void = @ptrFromInt(0x4286F0);

pub const swrQuad_SetColor: *fn (i: u16, r: u8, g: u8, b: u8, a: u8) callconv(.C) void = @ptrFromInt(0x428740);

// Loading

pub const TriggerLoad_InRace: *fn (jdge: usize, magic: u32) callconv(.C) void = @ptrFromInt(0x45D0B0);
