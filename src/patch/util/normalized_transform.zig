const std = @import("std");

pub inline fn flip(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return 1 - n;
}

pub inline fn pow2(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return n * n;
}

pub inline fn pow3(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return n * n * n;
}

// TODO: naming
pub inline fn fadeOut2(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return flip(pow2(n));
}

// TODO: naming
pub inline fn fadeIn2(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return flip(pow2(flip(n)));
}

pub fn smooth2(n: f32) f32 {
    std.debug.assert(n >= -1 and n <= 1);
    return std.math.fabs(n) * n;
}
