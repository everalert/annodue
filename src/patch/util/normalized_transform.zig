const std = @import("std");

pub inline fn xfade(n1: f32, n2: f32, weight: f32) f32 {
    std.debug.assert(n1 >= 0 and n1 <= 1);
    std.debug.assert(n2 >= 0 and n2 <= 1);
    return n1 + weight * (n2 - n1);
}

pub inline fn flip(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return 1 - n;
}

// TODO: naming, smoothStart2
pub inline fn pow2(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return n * n;
}

// TODO: naming, smoothStart3
pub inline fn pow3(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return n * n * n;
}

// TODO: naming, smoothStart4
pub inline fn pow4(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return n * n * n * n;
}

// TODO: naming, smoothStart5
pub inline fn pow5(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return n * n * n * n * n;
}

// TODO: naming, sign-preserving smoothStart2
pub fn smooth2(n: f32) f32 {
    std.debug.assert(n >= -1 and n <= 1);
    return std.math.fabs(n) * n;
}

// TODO: naming, sign-preserving smoothStart2
pub fn smooth4(n: f32) f32 {
    std.debug.assert(n >= -1 and n <= 1);
    return std.math.fabs(n) * n * n * n;
}

// TODO: naming
pub inline fn fadeOut2(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return flip(pow2(n));
}

// TODO: naming, smoothStop2
pub inline fn fadeIn2(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return flip(pow2(flip(n)));
}

// TODO: naming, smoothStop3
pub inline fn fadeIn3(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return flip(pow3(flip(n)));
}

// TODO: naming, smoothStop4
pub inline fn fadeIn4(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return flip(pow4(flip(n)));
}

// TODO: naming, smoothStop5
pub inline fn fadeIn5(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return flip(pow5(flip(n)));
}

pub inline fn smoothStep2(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return xfade(pow2(n), fadeIn2(n), n);
}

pub inline fn smoothStep3(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return xfade(pow3(n), fadeIn3(n), n);
}

pub inline fn smoothStep4(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return xfade(pow4(n), fadeIn4(n), n);
}

pub inline fn smoothStep5(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return xfade(pow5(n), fadeIn5(n), n);
}

pub inline fn smoothStart5Stop2(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return xfade(pow5(n), fadeIn2(n), n);
}
