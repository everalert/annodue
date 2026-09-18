const std = @import("std");
const assert = std.debug.assert;

pub fn RoundIntUp(comptime T: type, n: T, inc: T) T {
    comptime assert(@typeInfo(T) == .Int or @typeInfo(T) == .ComptimeInt);
    const v: T = n + inc - 1;
    return v - @mod(v, inc);
}

pub fn RoundIntDown(comptime T: type, n: T, inc: T) T {
    comptime assert(@typeInfo(T) == .Int or @typeInfo(T) == .ComptimeInt);
    return n - @mod(n, inc);
}

test "RoundInt" {
    try std.testing.expect(50 == RoundIntUp(u32, 49, 10));
    try std.testing.expect(50 == RoundIntUp(u32, 50, 10));
    try std.testing.expect(60 == RoundIntUp(u32, 51, 10));
    try std.testing.expect(-40 == RoundIntUp(i32, -49, 10));
    try std.testing.expect(-50 == RoundIntUp(i32, -50, 10));
    try std.testing.expect(-50 == RoundIntUp(i32, -51, 10));
    //try std.testing.expect(60 == RoundIntUp(f32, 51, 10)); // integers only
    //try std.testing.expect(40 == RoundIntUp(i32, 51, -10)); // positive inc only

    try std.testing.expect(40 == RoundIntDown(u32, 49, 10));
    try std.testing.expect(50 == RoundIntDown(u32, 50, 10));
    try std.testing.expect(50 == RoundIntDown(u32, 51, 10));
    try std.testing.expect(-50 == RoundIntDown(i32, -49, 10));
    try std.testing.expect(-50 == RoundIntDown(i32, -50, 10));
    try std.testing.expect(-60 == RoundIntDown(i32, -51, 10));
    //try std.testing.expect(50 == RoundIntDown(f32, 51, 10)); // integers only
    //try std.testing.expect(40 == RoundIntDown(i32, 51, -10)); // positive inc only
}

//------------------------------------------------------------------------------
// geometry
// TODO: ?? probably move to libannodue math subgroup; not sure how to organize yet

// TODO: ?? pass enclosed zero-size case (true == CollisionStrict1D(u8, 2, 5, 3, 3))
// "strict" (surfaces must be separate) as opposed to "standard" (surfaces may
// occupy exactly the same point as long as their insides don't intersect)
/// slice-style collision check, where n2 values represent first integer
/// value that is out-of-range (i.e. a2==b1 is not a collision)
pub fn CollisionStrict1D(comptime T: type, a1: T, a2: T, b1: T, b2: T) bool {
    assert(a1 <= a2);
    assert(b1 <= b2);
    const st_max = @max(a1, b1);
    const ed_min = @min(a2, b2);
    return st_max < ed_min or ed_min > st_max;
}

test "CollisionStrict1D" {
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 5, 1, 2)); // outside left
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 5, 5, 6)); // outside right
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 5, 2, 2)); // zero-length left
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 5, 5, 5)); // zero-length right
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 1, 3)); // partial left
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 4, 6)); // partial right
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 1, 6)); // encompassing
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 3, 4)); // enclosed
    //try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 3, 3)); // enclosed, zero size
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 2, 5)); // equal
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 2, 2, 2)); // equal both zero
}
