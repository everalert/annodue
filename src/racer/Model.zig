const std = @import("std");

const vec = @import("Vector.zig");
const Vec3 = vec.Vec3;
const mat = @import("Matrix.zig");
const Mat4x3 = mat.Mat4x3;
const Mat4x4 = mat.Mat4x4;

// GAME FUNCTIONS

pub const Node_SetTransform: *fn (*ModelNodeXf, *Mat4x4) callconv(.C) void = @ptrFromInt(0x431640);
pub const Node_SetFlags: *fn (*ModelNode, i32, i32, i8, i32) callconv(.C) void = @ptrFromInt(0x431A50);
pub const Node_SetColorsOnAllMaterials: *fn (*ModelNode, unk2: u8, unk1: u8, R: u8, G: u8, B: u8, A: u8) callconv(.C) void = @ptrFromInt(0x42B640);

pub const MeshMaterial_SetColors: *fn (*ModelMeshMaterial, unk2: i16, unk1: i16, R: i16, G: i16, B: i16, A: i16) callconv(.C) void = @ptrFromInt(0x42B640);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

// TODO: assert len 0x1C
pub const ModelNode = extern struct {
    Type: u32, // TODO: NodeType enum def
    Flags1: u32,
    Flags2: u32,
    Flags3: u16,
    LightIndex: u16,
    Flags5: u32,
    ChildrenCount: u32,
    Payload: extern union {
        pChildren: [*]*ModelNode,
        pMeshes: [*]*ModelMesh,
    },
};

pub const ModelNodeXf = extern struct {
    Node: ModelNode,
    Transform: Mat4x3,
};

// TODO
pub const ModelMesh = extern struct {};

// TODO
pub const ModelMeshMaterial = extern struct {};

// TODO
pub const ModelAnimation = extern struct {};

// size 0x2C
pub const ModelTriggerDescription = extern struct {
    Center: Vec3,
    Direction: Vec3, // orientation?
    SizeXY: f32,
    SizeZ: f32,
    pModelNode: *ModelNode,
    Type: u16,
    Flags: u16,
    pNext: *ModelTriggerDescription,
};

// HELPERS

// ...
