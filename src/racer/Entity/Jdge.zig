const std = @import("std");

// FIXME: move pause menu stuff out of Jdge?

const e = @import("entity.zig");
const m = @import("../Model.zig");
const ModelNodeXf = m.ModelNodeXf;

const w32 = @import("zigwin32");
const BOOL = w32.foundation.BOOL;

// GAME FUNCTIONS

pub const fnQueueLoad: *const fn (jdge: *Jdge, magic: u32) callconv(.C) void = @ptrFromInt(0x45D0B0);

pub const fnStage14: *const fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x45E200);
//pub const fnStage18: *fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x00);
pub const fnStage1C: *const fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x45EA30);
pub const fnStage20: *const fn (jdge: *Jdge) callconv(.C) void = @ptrFromInt(0x463580);
pub const fnEvent: *const fn (jdge: *Jdge, magic: *e.MAGIC_EVENT, payload: u32) callconv(.C) void = @ptrFromInt(0x463A50);

pub const fnPauseMenuOpen: *const fn () callconv(.C) void = @ptrFromInt(0x445680);
pub const fnPauseMenuClose: *const fn () callconv(.C) void = @ptrFromInt(0x445780);
// GAME CONSTANTS

pub const LOAD_QUEUED: *BOOL = @ptrFromInt(0x50CA34);

// TODO: work through fn_45F230 and related, and characterize this properly. also
//  need to find related values; this seems to be a transitional animation value
//  for the different minimap modes, however some aspects of the minimap are not
//  tracked yet, such as the mode itself, as well as there being a frame delay in
//  the minimap element rendering
pub const UI_MINIMAP_TIMING_UNK_01: *f32 = @ptrFromInt(0x4C5298);

// TODO: work through fn_4611F0 and characterize the individual arrays. both blocks
//  contain a series of [2]f32 arrays tracking various aspects of the player engine
//  UI animation and sound effects
pub const UI_ENGINE_TIMING_BLOCK_01: *[4]f32 = @ptrFromInt(0x4C52A0);
pub const UI_ENGINE_TIMING_BLOCK_02: *[10]f32 = @ptrFromInt(0x50CA60);

// TODO: PauseMenuState enum
pub const PAUSE_MENU_STATE: *i32 = @ptrFromInt(0x50C5F0);

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
pub fn hCouldPause(jdge: *Jdge) bool {
    if (jdge.Flags._05_cannot_pause)
        return false;
    switch (jdge.Flags.RACE_STATE) {
        .PostRace, .CameraSweepInit, .CameraSweep, .Loading => return false,
        else => return true,
    }
}
