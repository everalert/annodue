const std = @import("std");
const BOOL = std.os.windows.BOOL;

// GAME FUNCTIONS

// NOTE: strings found at 0x4B7A44 in game memory
/// @filename   a .znm file located in /data/anims
pub const Rand: *fn () callconv(.C) i32 = @ptrFromInt(0x4816B0);

// GAME CONSTANTS

pub const IS_SEEDED_ADDR: usize = 0x50CB80;
pub const IS_SEEDED: *BOOL = @ptrFromInt(IS_SEEDED_ADDR);
pub const NUMBER_ADDR: usize = 0x50CB7C;
pub const NUMBER: *i32 = @ptrFromInt(NUMBER_ADDR);

// HELPERS

// ...
