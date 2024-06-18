const std = @import("std");

const e = @import("entity.zig");
const m = @import("../Model.zig");
const ModelNodeXf = m.ModelNodeXf;

// GAME FUNCTIONS

pub const TriggerLoad_InRace: *fn (jdge: *Jdge, magic: u32) callconv(.C) void = @ptrFromInt(0x45D0B0);

pub const fnStage14: *fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x45E200);
//pub const fnStage18: *fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x00);
pub const fnStage1C: *fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x45EA30);
pub const fnStage20: *fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x463580);
pub const fnEvent: *fn (jdge: *Jdge, magic: *e.MAGIC_EVENT, payload: u32) callconv(.C) void = @ptrFromInt(0x463A50);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

pub const SIZE: usize = e.EntitySize(.Jdge);

// TODO: testing assertion of size correctness
pub const Jdge = extern struct {
    EntityMagic: u32,
    EntityFlags: u32,
    Flags: u32,
    RaceTimer: f32,
    pSplineMarkers: [6]*ModelNodeXf,
    _unk_028_63: [0x64 - 0x28]u8,
    _unkmat44_064: [16]f32, // TODO: typedef
    _unkmat44_0A4: [16]f32, // TODO: typedef
    _unkmat44_0E4: [16]f32, // TODO: typedef
    _hud_mode: i32,
    EventMagic: u32,
    _unk_12C_163: [0x164 - 0x12C]u8,
    _unkmat44_164: [16]f32, // TODO: typedef
    _unk_1A4_1AF: [0x1B0 - 0x1A4]u8,
    _modelblock_index: i32,
    _unk_1B4_1BB: [8]u8,
    Racers: u32,
    _unk_1C0_1C7: [8]u8,
    Laps: u32,
    _unk_1C8_1CB: [4]u8,
    RecordLap1: f32,
    RecordLap3: f32,
    _unk_1D8_1E7: [0x20]u8,
};

// HELPERS

// ...
