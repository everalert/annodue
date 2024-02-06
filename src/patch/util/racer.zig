const std = @import("std");
const mem = @import("memory.zig");

pub const constants = @import("racer_const.zig");
pub const functions = @import("racer_fn.zig");
const c = constants;
const f = functions;

fn deref_entity(entity: c.ENTITY, index: u32, offset: usize) usize {
    return mem.deref(&.{
        c.ADDR_ENTITY_MANAGER_JUMP_TABLE,
        @intFromEnum(entity) * 4,
        0x10,
        c.EntitySize(entity) * index + offset,
    });
}

pub fn ReadEntityValue(entity: c.ENTITY, index: u32, offset: usize, comptime T: type) T {
    const address = deref_entity(entity, index, offset);
    return mem.read(address, T);
}

pub fn ReadEntityValueBytes(entity: c.ENTITY, index: u32, offset: usize, out: ?*anyopaque, len: usize) void {
    const address = deref_entity(entity, index, offset);
    mem.read_bytes(address, out, len);
}

pub fn WriteEntityValue(entity: c.ENTITY, index: u32, offset: usize, comptime T: type, value: T) void {
    const address = deref_entity(entity, index, offset);
    _ = mem.write(address, T, value);
}

pub fn WriteEntityValueBytes(entity: c.ENTITY, index: u32, offset: usize, in: ?*anyopaque, len: usize) void {
    const address = deref_entity(entity, index, offset);
    _ = mem.write_bytes(address, in, len);
}
