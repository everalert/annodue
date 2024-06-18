const std = @import("std");

const vec = @import("Vector.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;

// GAME FUNCTIONS

pub const Mat4x4_Mul: *const fn (out: *Mat4x4, in1: *Mat4x4, in2: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x42FB70);
pub const Mat4x4_MulSelf: *const fn (in_out: *Mat4x4, in2: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x42FF80);

pub const Mat4x4_SetRotation: *const fn (out: *Mat4x4, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x430E00);

pub const Mat4x4_InitRotated: *const fn (out: *Mat4x4, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x431020);
pub const Mat4x4_InitQuat: *const fn (out: *Mat4x4, a: f32, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x431150);
pub const Mat4x4_InitQuatMul: *const fn (out: *Mat4x4, a: f32, x: f32, y: f32, z: f32, in: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x431390);
pub const Mat4x4_Init: *const fn (out: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x4313D0);

pub const Mat4x4_MulQuat: *const fn (out: *Mat4x4, in: *Mat4x4, a: f32, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x431410);

pub const Mat4x4_ScaleAxes: *const fn (out: *Mat4x4, x: f32, y: f32, z: f32, in: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x431450);

pub const Mat4x4_Copy4x3: *const fn (out: *Mat4x4, in: *Mat4x3) callconv(.C) void =
    @ptrFromInt(0x44BAD0);
pub const Mat4x4_Copy: *const fn (out: *Mat4x4, in: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x44BB10);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

pub const Mat4x4 = extern struct {
    _00: Vec4,
    _10: Vec4,
    _20: Vec4,
    _30: Vec4,
};

pub const Mat4x3 = extern struct {
    _00: Vec3,
    _10: Vec3,
    _20: Vec3,
    _30: Vec3,
};

// ...

// HELPERS

// ...
