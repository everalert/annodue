const std = @import("std");

const vec = @import("Vector.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;

// GAME FUNCTIONS

// NOTE: 'quaternion' functions actually take axis-angle input, then do AA->quat->mat4 conversion

pub const Mat4x4_Mul: *fn (out: *Mat4x4, in1: *Mat4x4, in2: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x42FB70);
pub const Mat4x4_MulSelf: *fn (in_out: *Mat4x4, in2: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x42FF80);

pub const Mat4x4_GetLocation: *fn (in: *Mat4x4, out: *Location) callconv(.C) void =
    @ptrFromInt(0x430B80);
pub const Mat4x4_SetRotation: *fn (out: *Mat4x4, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x430E00);

pub const Mat4x4_InitRotated: *fn (out: *Mat4x4, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x431020);
pub const Mat4x4_InitLocation: *fn (out: *Mat4x4, in: *Location) callconv(.C) void =
    @ptrFromInt(0x431060);
pub const Mat4x4_InitTranslated: *fn (out: *Mat4x4, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x431100);
pub const Mat4x4_InitQuat: *fn (out: *Mat4x4, a: f32, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x431150);
pub const Mat4x4_InitQuatMul: *fn (out: *Mat4x4, a: f32, x: f32, y: f32, z: f32, in: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x431390);
pub const Mat4x4_Init: *fn (out: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x4313D0);

pub const Mat4x4_MulQuat: *fn (out: *Mat4x4, in: *Mat4x4, a: f32, x: f32, y: f32, z: f32) callconv(.C) void =
    @ptrFromInt(0x431410);

pub const Mat4x4_ScaleAxes: *fn (out: *Mat4x4, x: f32, y: f32, z: f32, in: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x431450);

pub const Mat4x4_Copy4x3: *fn (out: *Mat4x4, in: *Mat4x3) callconv(.C) void =
    @ptrFromInt(0x44BAD0);
pub const Mat4x4_Copy: *fn (out: *Mat4x4, in: *Mat4x4) callconv(.C) void =
    @ptrFromInt(0x44BB10);

pub const Mat4x3_InvertOrthoNorm: *fn (out: *Mat4x3, in: *Mat4x3) callconv(.C) void =
    @ptrFromInt(0x492680);
pub const Mat4x3_Mul: *fn (out: *Mat4x3, in1: *Mat4x3, in2: *Mat4x3) callconv(.C) void =
    @ptrFromInt(0x492B70);

pub const Mat4x3_TransformPoint: *fn (out: *Vec3, in_v: *const Vec3, in_m: *const Mat4x3) callconv(.C) void =
    @ptrFromInt(0x493200);
pub const Mat4x3_TransformPointsList: *fn (in_m: *const Mat4x3, in_v: *const Vec3, out_v: *Vec3, count: i32) callconv(.C) void =
    @ptrFromInt(0x493270);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

pub const Mat4x4 = extern struct {
    X: Vec4 = .{ .x = 1, .y = 0, .z = 0, .w = 0 },
    Y: Vec4 = .{ .x = 0, .y = 1, .z = 0, .w = 0 },
    Z: Vec4 = .{ .x = 0, .y = 0, .z = 1, .w = 0 },
    T: Vec4 = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
};

pub const Mat4x3 = extern struct {
    X: Vec3 = .{ .x = 1, .y = 0, .z = 0 },
    Y: Vec3 = .{ .x = 0, .y = 1, .z = 0 },
    Z: Vec3 = .{ .x = 0, .y = 0, .z = 1 },
    T: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
};

// TODO: relocate once things get more ironed out
pub const Location = extern struct {
    T: Vec3 = .{}, // translation
    R: Vec3 = .{}, // rotation
};

// ...

// HELPERS

// ...
