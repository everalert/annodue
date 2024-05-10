const std = @import("std");
const mem = @import("memory.zig");

const racer = @import("racer");
const rd = racer.RaceData;
const e = racer.Entity;
const c = racer.constants;
const f = racer.functions;
const t = racer.text;

// ENTITY SYSTEM

pub fn DerefEntity(entity: e.ENTITY, index: u32, offset: usize) usize {
    return mem.deref(&.{
        e.MANAGER_JUMPTABLE_ADDR,
        @intFromEnum(entity) * 4,
        0x10,
        e.EntitySize(entity) * index + offset,
    });
}

pub fn ReadEntityValue(entity: e.ENTITY, index: u32, offset: usize, comptime T: type) T {
    const address = DerefEntity(entity, index, offset);
    return mem.read(address, T);
}

pub fn ReadEntityValueBytes(entity: e.ENTITY, index: u32, offset: usize, out: ?*anyopaque, len: usize) void {
    const address = DerefEntity(entity, index, offset);
    mem.read_bytes(address, out, len);
}

pub fn WriteEntityValue(entity: e.ENTITY, index: u32, offset: usize, comptime T: type, value: T) void {
    const address = DerefEntity(entity, index, offset);
    _ = mem.write(address, T, value);
}

pub fn WriteEntityValueBytes(entity: e.ENTITY, index: u32, offset: usize, in: ?*anyopaque, len: usize) void {
    const address = DerefEntity(entity, index, offset);
    _ = mem.write_bytes(address, in, len);
}

// SCREEN SPACE QUAD DRAWING

pub fn InitNewQuad(spr: u32) u16 {
    const i: u16 = mem.read(c.ADDR_QUAD_INITIALIZED_INDEX, u16);
    f.swrQuad_InitQuad(i, spr);
    _ = mem.write(c.ADDR_QUAD_INITIALIZED_INDEX, u16, i + 1);
    return i;
}
