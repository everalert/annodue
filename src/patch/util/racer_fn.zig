pub const Self = @This();

// Text

pub const swrText_CreateEntry: *fn (x: u16, y: u16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8, font: i32, entry2: u32) callconv(.C) void = @ptrFromInt(0x4503E0);

pub const swrText_CreateEntry1: *fn (x: u16, y: u16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x450530);

pub const swrText_CreateEntry2: *fn (x: u16, y: u16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x4505C0);

// Loading

pub const TriggerLoad_InRace: *fn (jdge: usize, magic: u32) callconv(.C) void = @ptrFromInt(0x45D0B0);
