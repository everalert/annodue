const std = @import("std");

const e = @import("entity.zig");
const m = @import("../Model.zig");
const ModelNodeXf = m.ModelNodeXf;

const w32 = @import("zigwin32");
const BOOL = w32.foundation.BOOL;

// GAME FUNCTIONS

pub const QueueLoad: *fn (jdge: *Jdge, magic: u32) callconv(.C) void = @ptrFromInt(0x45D0B0);

pub const fnStage14: *fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x45E200);
//pub const fnStage18: *fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x00);
pub const fnStage1C: *fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x45EA30);
pub const fnStage20: *fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x463580);
pub const fnEvent: *fn (jdge: *Jdge, magic: *e.MAGIC_EVENT, payload: u32) callconv(.C) void = @ptrFromInt(0x463A50);

// GAME CONSTANTS

pub const LOAD_QUEUED: *BOOL = @ptrFromInt(0x50CA34);

// GAME TYPEDEFS

pub const SIZE: usize = e.EntitySize(.Jdge);

// TODO: testing assertion of size correctness
pub const Jdge = extern struct {
    EntityMagic: u32,
    EntityFlags: u32,
    Flags: JDGE_FLAGS,
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

// TODO: testing assert size 32 bits
pub const JDGE_FLAGS = packed struct {
    RACE_STATE: enum(u4) {
        Countdown,
        Racing,
        PostRace,
        _3,
        CameraSweepInit,
        CameraSweep,
        Loading,
    },
    _04: bool,
    _05_cannot_pause: bool,
    _06: bool,
    _07: bool,
    COUNT_3_SOUND_NOT_PLAYED: bool,
    COUNT_2_SOUND_NOT_PLAYED: bool,
    COUNT_1_SOUND_NOT_PLAYED: bool,
    _11: bool,
    _12_31: u20, // NOTE: may be unused
};

// HELPERS

// based on fn_462D40 (Pause_ShouldPause)
pub fn CouldPause(jdge: *Jdge) bool {
    if (jdge.Flags._05_cannot_pause)
        return false;
    switch (jdge.Flags.RACE_STATE) {
        .PostRace, .CameraSweepInit, .CameraSweep, .Loading => return false,
        else => return true,
    }
}
