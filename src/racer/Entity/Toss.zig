const std = @import("std");
const e = @import("entity.zig");

pub const SIZE: usize = e.EntitySize(.Toss);

pub const Toss = extern struct {
    entity_magic: u32,
    entity_flags: u32,
    _unk_000_END: [SIZE - 8]u8,
};
