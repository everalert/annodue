const std = @import("std");

// TODO: move stuff from cam7 here

pub const Mat4x4 = packed struct {
    x: [4]f32 = .{ 1, 0, 0, 0 },
    y: [4]f32 = .{ 0, 1, 0, 0 },
    z: [4]f32 = .{ 0, 0, 1, 0 },
    t: [4]f32 = .{ 0, 0, 0, 1 },
};

pub const Pos3D = extern struct {
    const Self = @This();
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn dif(self: *Self, other: *Self) Self {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn distance(self: *Self, other: *Self) f32 {
        const step = self.dif(other);
        return std.math.sqrt(step.x * step.x + step.y * step.y + step.z * step.z);
    }

    pub fn distanceXY(self: *Self, other: *Self) f32 {
        const step = self.dif(other);
        return std.math.sqrt(step.x * step.x + step.y * step.y);
    }
};
