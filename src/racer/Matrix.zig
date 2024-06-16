const std = @import("std");

const vec = @import("Vector.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;

// GAME FUNCTIONS

// ...

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
