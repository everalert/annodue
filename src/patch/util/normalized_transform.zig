const std = @import("std");
const m = std.math;

// assertions

const EPSILON: f32 = std.math.floatEps(f32);
const EPSILON_P1: f32 = 1 + EPSILON;
const EPSILON_N1: f32 = -1 - EPSILON;

pub inline fn assertRangePos(n: f32) void {
    std.debug.assert(n >= -EPSILON and n <= EPSILON_P1);
}

pub inline fn assertRangeNeg(n: f32) void {
    std.debug.assert(n <= EPSILON and n >= EPSILON_N1);
}

pub inline fn assertRangeBoth(n: f32) void {
    std.debug.assert(n <= EPSILON_P1 and n >= EPSILON_N1);
}

// util

pub inline fn xfade(n1: f32, n2: f32, weight: f32) f32 {
    assertRangePos(n1);
    assertRangePos(n2);
    return n1 + weight * (n2 - n1);
}

pub inline fn flip(n: f32) f32 {
    assertRangePos(n);
    return 1 - n;
}

// smoothstart

// TODO: naming, smoothStart2
pub inline fn pow2(n: f32) f32 {
    assertRangePos(n);
    return n * n;
}

// TODO: naming, smoothStart3
pub inline fn pow3(n: f32) f32 {
    assertRangePos(n);
    return n * n * n;
}

// TODO: naming, smoothStart4
pub inline fn pow4(n: f32) f32 {
    assertRangePos(n);
    return n * n * n * n;
}

// TODO: naming, smoothStart5
pub inline fn pow5(n: f32) f32 {
    assertRangePos(n);
    return n * n * n * n * n;
}

// sign-aware smoothstart

// TODO: naming, sign-preserving smoothStart2
pub fn smooth2(n: f32) f32 {
    assertRangeBoth(n);
    return std.math.fabs(n) * n;
}

// TODO: naming, sign-preserving smoothStart3
pub fn smooth3(n: f32) f32 {
    assertRangeBoth(n);
    return std.math.fabs(n) * n * n;
}

// TODO: naming, sign-preserving smoothStart4
pub fn smooth4(n: f32) f32 {
    assertRangeBoth(n);
    return std.math.fabs(n) * n * n * n;
}

// ??

// TODO: naming
pub inline fn fadeOut2(n: f32) f32 {
    assertRangePos(n);
    return flip(pow2(n));
}

// smoothstop

// TODO: naming, smoothStop2
pub inline fn fadeIn2(n: f32) f32 {
    assertRangePos(n);
    return flip(pow2(flip(n)));
}

// TODO: naming, smoothStop3
pub inline fn fadeIn3(n: f32) f32 {
    assertRangePos(n);
    return flip(pow3(flip(n)));
}

// TODO: naming, smoothStop4
pub inline fn fadeIn4(n: f32) f32 {
    assertRangePos(n);
    return flip(pow4(flip(n)));
}

// TODO: naming, smoothStop5
pub inline fn fadeIn5(n: f32) f32 {
    assertRangePos(n);
    return flip(pow5(flip(n)));
}

// smoothstep

pub inline fn smoothStep2(n: f32) f32 {
    assertRangePos(n);
    return xfade(pow2(n), fadeIn2(n), n);
}

pub inline fn smoothStep3(n: f32) f32 {
    assertRangePos(n);
    return xfade(pow3(n), fadeIn3(n), n);
}

pub inline fn smoothStep4(n: f32) f32 {
    assertRangePos(n);
    return xfade(pow4(n), fadeIn4(n), n);
}

pub inline fn smoothStep5(n: f32) f32 {
    assertRangePos(n);
    return xfade(pow5(n), fadeIn5(n), n);
}

// smooth start-stop (smoothmix?)

pub inline fn smoothStart5Stop2(n: f32) f32 {
    assertRangePos(n);
    return xfade(pow5(n), fadeIn2(n), n);
}
