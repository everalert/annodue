const std = @import("std");

const nxf = @import("normalized_transform.zig");

pub fn flash_color(color: u32, time: f32, dur: f32) u32 {
    if (time >= dur) return color;

    var c = color;
    var col: [4]u8 align(4) = @as(*[4]u8, @ptrCast(&c)).*;

    const tscale: f32 = nxf.pow2(nxf.flip(time / dur));
    const cycle: f32 = @cos(time * std.math.pi * 12) * 0.5 + 0.5;
    for (0..4) |i| col[i] -= @intFromFloat(@as(f32, @floatFromInt(col[i] / 2)) * cycle * tscale);

    return @as(*u32, @ptrCast(&col)).*;
}
