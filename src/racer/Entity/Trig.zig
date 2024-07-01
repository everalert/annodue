const std = @import("std");
const BOOL = std.os.windows.BOOL;

const vec = @import("../Vector.zig");
const Vec3 = vec.Vec3;
const mat = @import("../Matrix.zig");
const Mat4x4 = mat.Mat4x4;

const model = @import("../Model.zig");
const ModelNode = model.ModelNode;
const ModelMeshMaterial = model.ModelMeshMaterial;
const ModelAnimation = model.ModelAnimation;
const ModelTriggerDescription = model.ModelTriggerDescription;

const e = @import("entity.zig");
const Test = e.Test.Test;

// GAME FUNCTIONS

pub const HandleTriggers: *fn (*Trig, *Test, is_local: BOOL) callconv(.C) void = @ptrFromInt(0x47CE60);

pub const fnStage14: *fn (*Trig) callconv(.C) void = @ptrFromInt(0x47C390);
//pub const fnStage18: *fn (*Trig) callconv(.C) void = @ptrFromInt(0x00);
pub const fnStage1C: *fn (*Trig) callconv(.C) void = @ptrFromInt(0x47C500);
//pub const fnStage20: *fn (*Trig) callconv(.C) void = @ptrFromInt(0x00);
pub const fnEvent: *fn (*Trig, magic: *e.MAGIC_EVENT, payload: u32) callconv(.C) void = @ptrFromInt(0x47C710);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

pub const SIZE: usize = e.EntitySize(.Trig);

pub const Trig = extern struct {
    EntityMagic: u32,
    EntityFlags: u32,
    Type: u32,
    Flags: u32,
    _10_timer: f32,
    _14_timer: f32,
    _unk_18_24: [0x0C]u8,
    TriggerCenter: Vec3,
    _unk_30: Vec3,
    _unk_3C: *ModelNode,
    _unk_40: *ModelAnimation,
    _unk_44: *ModelAnimation,
    _unk_48: *ModelNode,
    pTrigDesc: *ModelTriggerDescription,
    pTestXf: *Mat4x4,
    _unk_54: *ModelMeshMaterial,
};

// HELPERS

// ...
