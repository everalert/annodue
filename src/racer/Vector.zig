const std = @import("std");

const mat = @import("Matrix.zig");
const Mat4x3 = mat.Mat4x3;
const Mat4x4 = mat.Mat4x4;

// GAME FUNCTIONS

pub const Vec2_Add: *fn (in1: *Vec2, in2: *Vec2) callconv(.C) void =
    @ptrFromInt(0x42F6E0);
pub const Vec2_Scale: *fn (out: *Vec2, sc1: f32, in1: *Vec2) callconv(.C) void =
    @ptrFromInt(0x42F700);
pub const Vec2_AddScaled: *fn (out: *Vec2, in1: *Vec2, sc2: f32, in2: *Vec2) callconv(.C) void =
    @ptrFromInt(0x42F720);
pub const Vec2_Mag: *fn (in: *const Vec2) callconv(.C) f32 =
    @ptrFromInt(0x42F750);
pub const Vec2_Norm: *fn (out: *Vec2) callconv(.C) void =
    @ptrFromInt(0x42F780);

pub const Vec3_Set: *fn (out: *Vec3, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x42F7B0);
pub const Vec3_Copy: *fn (out: *Vec3, in: *const Vec3) callconv(.C) void =
    @ptrFromInt(0x42F7D0);
pub const Vec3_Eql: *fn (in1: *const Vec3, in2: *const Vec3) callconv(.C) bool =
    @ptrFromInt(0x42F7F0);
pub const Vec3_Add: *fn (out: *Vec3, in1: *const Vec3, in2: *const Vec3) callconv(.C) void =
    @ptrFromInt(0x42F830);
pub const Vec3_Sub: *fn (out: *Vec3, in1: *const Vec3, in2: *const Vec3) callconv(.C) void =
    @ptrFromInt(0x42F860);
pub const Vec3_Dot: *fn (in1: *const Vec3, in2: *const Vec3) callconv(.C) f32 =
    @ptrFromInt(0x42F890);
pub const Vec3_Mag: *fn (in: *const Vec3) callconv(.C) f32 =
    @ptrFromInt(0x42F8C0);
pub const Vec3_DistSq: *fn (in1: *const Vec3, in2: *const Vec3) callconv(.C) f32 =
    @ptrFromInt(0x42F910);
pub const Vec3_Dist: *fn (in1: *const Vec3, in2: *const Vec3) callconv(.C) f32 =
    @ptrFromInt(0x42F950);
pub const Vec3_MulMat4x4: *fn (out: *Vec3, in1: *const Vec3, in2: *const Mat4x4) callconv(.C) void =
    @ptrFromInt(0x430980);
pub const Vec3_Norm: *fn (out: *Vec3) callconv(.C) void =
    @ptrFromInt(0x42F9B0);
pub const Vec3_Cross: *fn (out: *Vec3, in1: *const Vec3, in2: *const Vec3) callconv(.C) void =
    @ptrFromInt(0x42F9F0);
pub const Vec3_Scale: *fn (out: *Vec3, sc: f32, in: *const Vec3) callconv(.C) void =
    @ptrFromInt(0x42FA50);
pub const Vec3_AddScale1: *fn (out: *Vec3, in1: *const Vec3, sc2: f32, in2: *const Vec3) callconv(.C) void =
    @ptrFromInt(0x42FA80);
pub const Vec3_AddScale2: *fn (out: *Vec3, sc1: f32, in1: *const Vec3, sc2: f32, in2: *const Vec3) callconv(.C) void =
    @ptrFromInt(0x42FAC0);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

pub const Vec2 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Vec3 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

pub const Vec4 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,
};

// ...

// HELPERS

// ...
