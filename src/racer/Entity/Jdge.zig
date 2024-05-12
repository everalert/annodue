const std = @import("std");
const e = @import("entity.zig");

// GAME FUNCTIONS

pub const TriggerLoad_InRace: *fn (jdge: *Jdge, magic: u32) callconv(.C) void = @ptrFromInt(0x45D0B0);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

pub const SIZE: usize = e.EntitySize(.Jdge);

// TODO: testing assertion of size correctness
pub const Jdge = extern struct {
    entity_magic: u32,
    entity_flags: u32,
    flags: u32,
    raceTimer: f32,
    _unkptr_010: *anyopaque,
    _unkptr_014: *anyopaque,
    _unkptr_018: *anyopaque,
    _unkptr_01C: *anyopaque,
    _unkptr_020: *anyopaque,
    _unkptr_024: *anyopaque,
    _unk_028_63: [0x64 - 0x28]u8,
    _unkmat44_064: [16]f32, // TODO: typedef
    _unkmat44_0A4: [16]f32, // TODO: typedef
    _unkmat44_0E4: [16]f32, // TODO: typedef
    _hud_mode: i32,
    event_magic: u32,
    _unk_12C_163: [0x164 - 0x12C]u8,
    _unkmat44_164: [16]f32, // TODO: typedef
    _unk_1A4_1AF: [0x1B0 - 0x1A4]u8,
    _model_block_index: i32,
    _unk_1B4_1BB: [8]u8,
    racers: u32,
    _unk_1C0_1C7: [8]u8,
    laps: u32,
    _unk_1C8_1CB: [4]u8,
    recordLap1: f32,
    recordLap3: f32,
    _unk_1D8_1E7: [0x20]u8,
};

// HELPERS

// ...
