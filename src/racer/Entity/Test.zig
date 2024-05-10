const std = @import("std");
const e = @import("entity.zig");

pub const SIZE: usize = e.EntitySize(.Test);

pub const PLAYER_PTR_ADDR: usize = 0x4D78A8;
pub const PLAYER_PTR: *usize = @ptrFromInt(PLAYER_PTR_ADDR);
// TODO: double pointer; original data probably game state struct holding the ptr
pub const PLAYER: **Test = @ptrFromInt(PLAYER_PTR_ADDR);
pub const PLAYER_SLICE: **[SIZE]u8 = @ptrFromInt(PLAYER_PTR_ADDR); // TODO: convert to many-item pointer

pub const Test = extern struct {};
