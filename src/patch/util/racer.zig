const std = @import("std");
const mem = @import("memory.zig");

pub const constants = @import("racer_const.zig");
pub const functions = @import("racer_fn.zig");
const c = constants;
const f = functions;

// RACE DATA STRUCT

fn deref_racedata(offset: usize) usize {
    return mem.deref(&.{
        c.ADDR_RACE_DATA,
        offset,
    });
}

pub fn ReadRaceDataValue(offset: usize, comptime T: type) T {
    const address = deref_racedata(offset);
    return mem.read(address, T);
}

pub fn ReadRaceDataValueBytes(offset: usize, out: ?*anyopaque, len: usize) void {
    const address = deref_racedata(offset);
    mem.read_bytes(address, out, len);
}

pub fn WriteRaceDataValue(offset: usize, comptime T: type, value: T) void {
    const address = deref_racedata(offset);
    _ = mem.write(address, T, value);
}

pub fn WriteRaceDataValueBytes(offset: usize, in: ?*anyopaque, len: usize) void {
    const address = deref_racedata(offset);
    _ = mem.write_bytes(address, in, len);
}

// PLAYER TEST ENTITY

fn deref_player(offset: usize) usize {
    return mem.deref(&.{
        c.ADDR_RACE_DATA,
        0x84,
        offset,
    });
}

pub fn ReadPlayerValue(offset: usize, comptime T: type) T {
    const address = deref_player(offset);
    return mem.read(address, T);
}

pub fn ReadPlayerValueBytes(offset: usize, out: ?*anyopaque, len: usize) void {
    const address = deref_player(offset);
    mem.read_bytes(address, out, len);
}

pub fn WritePlayerValue(offset: usize, comptime T: type, value: T) void {
    const address = deref_player(offset);
    _ = mem.write(address, T, value);
}

pub fn WritePlayerValueBytes(offset: usize, in: ?*anyopaque, len: usize) void {
    const address = deref_player(offset);
    _ = mem.write_bytes(address, in, len);
}

// ENTITY SYSTEM

fn deref_entity(entity: c.ENTITY, index: u32, offset: usize) usize {
    return mem.deref(&.{
        c.ADDR_ENTITY_MANAGER_JUMPTABLE,
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

// SCREEN SPACE QUAD DRAWING

pub fn InitNewQuad(spr: u32) u16 {
    const i: u16 = mem.read(c.ADDR_QUAD_INITIALIZED_INDEX, u16);
    f.swrQuad_InitQuad(i, spr);
    _ = mem.write(c.ADDR_QUAD_INITIALIZED_INDEX, u16, i + 1);
    return i;
}
