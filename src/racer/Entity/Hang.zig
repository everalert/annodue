const std = @import("std");
const e = @import("entity.zig");

pub const SIZE: usize = e.EntitySize(.Hang);

pub const DRAW_MENU_JUMPTABLE_ADDR: usize = 0x457A88;
pub const DRAW_MENU_JUMPTABLE_SCENE_3_ADDR: usize = 0x457AD4;

pub const Hang = extern struct {};
