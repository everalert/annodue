const std = @import("std");

const mat = @import("Matrix.zig");
const Mat4x3 = mat.Mat4x3;
const Mat4x4 = mat.Mat4x4;

// GAME FUNCTIONS

pub const Vec3_Normalize: *const fn (out: *Vec3) callconv(.C) void =
    @ptrFromInt(0x42F9B0);
pub const Vec3_Magnitude: *const fn (in: *Vec3) callconv(.C) f32 =
    @ptrFromInt(0x42F8C0);
pub const Vec3_Set: *const fn (out: *Vec3, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x42F7B0);
pub const Vec3_Scale: *const fn (out: *Vec3, sc: f32, in: *Vec3) callconv(.C) void =
    @ptrFromInt(0x42FA50);
pub const Vec3_AddScale1: *const fn (out: *Vec3, in1: *Vec3, sc2: f32, in2: *Vec3) callconv(.C) void =
    @ptrFromInt(0x42FA80);
pub const Vec3_AddScale2: *const fn (out: *Vec3, sc1: f32, in1: *Vec3, sc2: f32, in2: *Vec3) callconv(.C) void =
    @ptrFromInt(0x42FAC0);
pub const Vec3_MulMat4x4: *const fn (out: *Vec3, in1: *Vec3, in2: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x430980);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

pub const Vec3 = extern struct {
    _0: f32,
    _1: f32,
    _2: f32,
};

pub const Vec4 = extern struct {
    _0: f32,
    _1: f32,
    _2: f32,
    _3: f32,
};

// ...

// HELPERS

// ...
