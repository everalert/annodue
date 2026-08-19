const std = @import("std");
const assert = std.debug.assert;

pub fn RoundIntUp(comptime T: type, n: T, inc: T) T {
    comptime if (@typeInfo(T) != .Int) @compileError("T must be an integer type");
    const v: T = n + inc - 1;
    return v - @mod(v, inc);
}

pub fn RoundIntDown(comptime T: type, n: T, inc: T) T {
    comptime if (@typeInfo(T) != .Int) @compileError("T must be an integer type");
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
