const mem = @import("memory.zig");

pub const constants = @import("racer_const.zig");
pub const functions = @import("racer_fn.zig");
const c = constants;
const f = functions;

pub fn ReadEntityValue(entity: c.ENTITY_ID, index: u32, offset: usize, comptime T: type) T {
    const entity_size: usize = if (index == 0) 0 else mem.deref_read(&.{
        c.ADDR_ENTITY_MANAGER_JUMP_TABLE,
        @intFromEnum(entity) * 4,
        0x0C,
    }, usize);
    return mem.deref_read(&.{
        c.ADDR_ENTITY_MANAGER_JUMP_TABLE,
        @intFromEnum(entity) * 4,
        0x10,
        entity_size * index + offset,
    }, T);
}
