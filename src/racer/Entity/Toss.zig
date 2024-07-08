const std = @import("std");

const BOOL = std.os.windows.BOOL;

const e = @import("entity.zig");
const Mat4x4 = @import("../Matrix.zig").Mat4x4;
const ModelNode = @import("../Model.zig").ModelNode;
const ModelMeshMaterial = @import("../Model.zig").ModelMeshMaterial;

// GAME FUNCTIONS

//pub const fnStage14: *fn (*Toss) callconv(.C) void = @ptrFromInt(0x00);
//pub const fnStage18: *fn (*Toss) callconv(.C) void = @ptrFromInt(0x00);
pub const fnStage1C: *fn (*Toss) callconv(.C) void = @ptrFromInt(0x47B9E0);
pub const fnStage20: *fn (*Toss) callconv(.C) void = @ptrFromInt(0x47BA30);
pub const fnEvent: *fn (*Toss, magic: *e.MAGIC_EVENT, payload: u32) callconv(.C) void = @ptrFromInt(0x47BBA0);

pub const CreateEffect: *fn (xf: *Mat4x4, r: u8, g: u8, b: u8, a: u8, duration: f32, unk7: i32) callconv(.C) BOOL = @ptrFromInt(0x47BC40);
pub const InitResources: *fn () callconv(.C) void = @ptrFromInt(0x47BC40);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

// size 0x7C
pub const SIZE: usize = e.EntitySize(.Toss);

pub const Toss = extern struct {
    entity_magic: u32,
    entity_flags: u32,
    _unk_08_10: [8]u8,
    _unk_10_ptr: *anyopaque,
    _unk_14_ptr: *anyopaque,
    _unk_18_1C: [4]u8,
    _unk_1C_20: i32,
    Transform: Mat4x4,
    _unk_60_64: [4]u8,
    _unk_64_68: i32,
    AnimTimer: f32,
    AnimDuration: f32,
    RGBA: [4]u8, // TODO: typedef
    pMeshMaterial: *ModelMeshMaterial,
    pModel: *ModelNode,
};

// HELPERS

// ...
