const std = @import("std");
const e = @import("entity.zig");

// GAME FUNCTIONS

pub const DoFirstPersonCamera: *fn (*cMan) callconv(.C) void = @ptrFromInt(0x4528B0);
pub const DoPreRaceSweep: *fn (*cMan) callconv(.C) void = @ptrFromInt(0x451EF0);
pub const DoPreRaceSweepEnd: *fn (*cMan) callconv(.C) void = @ptrFromInt(0x4525D0);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

pub const SIZE: usize = e.EntitySize(.cMan);

// TODO: testing assertion of size correctness
pub const cMan = extern struct {
    entity_magic: u32,
    entity_flags: u32,
    _unk_008: u32,
    _unk_00C: u32,
    _unk_010: u32,
    _unk_014: u32,
    _unk_018: u32,
    _unk_01C: u32,
    transform: [16]f32, // TODO: typdef
    _unk_060: u32,
    _unk_064: u32,
    _unk_068: u32,
    animStage: u32,
    animTimer: f32,
    MetaCamIndex: u32,
    CamStateIndex: u32,
    mode: u32,
    modeRespawn: u32,
    _unk_084: u32,
    _unk_088: u32,
    _unk_08C: u32,
    _unk_090: u32,
    _unk_094: u32,
    _unk_098: u32,
    _unk_09C: u32,
    _unk_0A0: u32,
    _unk_0A4: u32,
    _unk_0A8: u32,
    _unk_0AC: u32,
    _unk_0B0: u32,
    _unkmat44_0B4: [16]f32, // TODO: typedef
    pTest: ?*e.Test,
    _unk_0F8: u32,
    _unk_0FC: u32,
    _unk_100: u32,
    _unk_104: u32,
    focusTransform: [16]f32, // TODO: typedef
    _unk_148: u32,
    _unk_14C: u32,
    _unk_150: u32,
    _unk_154: u32,
    _unk_158: u32,
    _unk_15C: u32,
    _unk_160: u32,
    _unk_164: u32,
    _unk_168: u32,
    _unk_16C: u32,
    _unk_170: u32,
    _unk_174: u32,
    _unk_178: u32,
    _unk_17C: u32,
    _unk_180: u32,
    _unk_184: u32,
    _unk_188: u32,
    _unk_18C: u32,
    _unk_190: u32,
    _unk_194: u32,
    _unk_198: u32,
    _unk_19C: u32,
    _unk_1A0: u32,
    _unk_1A4: u32,
    _unk_1A8: u32,
    _unk_1AC: u32,
    _unk_1B0: u32,
    _unkstruct_1B4: [0x30]u8, // LapCompletionStruct
    _unkmat44_1E4: [16]f32, // TODO: typedef
    _staging_transform: [16]f32, // TODO: typedef
    _staging_transform_focus: [16]f32, // TODO: typedef
    _unk_2A4: u32, // pointer to terrain flags?
    fogFlags: u32,
    visualFlags: u32, // defaults to 0xFFFFFF00
    zoom: f32,
    _render_depth: f32,
    _unk_2B8: f32,
    fogCol: [3]u32, // TODO: typedef(rgb)
    fogColTarget: [3]u32, // TODO: typedef(rgb)
    fogDist: f32,
    fogDistTarget: f32, // also manages track visual segment load distance
    _unk_2DC: u32,
    _unk_2E0: u32,
    _unk_2E4: u32,
    _unk_2E8: u32,
    _unk_2EC: u32,
    _unk_2F0: u32,
    _unk_2F4: u32,
    _unk_2F8: u32,
    _unk_2FC: u32,
    _unk_300: u32,
    _unk_304: u32,
    _unk_308: u32,
    _unk_30C: u32,
    _unk_310: u32,
    _unk_314: u32,
    _unk_318: u32,
    _unk_31C: u32,
    _unk_320: u32,
    _unk_324: u32,
    _unk_328: u32,
    _unk_32C: u32,
    _unk_330: u32,
    _unk_334: u32,
    _unk_338: u32,
    _unk_33C: u32,
    _unk_340: u32,
    _unk_344: u32,
    _unk_348: u32,
    _unk_34C: u32,
    _unk_350: u32,
    _unk_354: u32,
    _unk_358: u32,
    _unk_35C: u32,
    _unk_360: u32,
    _unk_364: u32,
    _unk_368: u32,
    _unk_36C: u32,
    _unk_370: u32,
    _unk_374: u32,
    _unk_378: u32,
    _unk_37C: u32,
    _unk_380: u32,
    _unk_384: u32,
    _unk_388: u32,
    _unk_38C: u32,
    _unk_390: u32,
    _unk_394: u32,
    _unk_398: u32,
    camShakeOffset: f32,
    camShakeSpeed: f32,
    camShakeOffsetMax: f32,
};
