const std = @import("std");
const assert = std.debug.assert;

// TODO: versions of greater/smaller search functions that wrap to the next value
//  on failure if possible instead of returning null. for bitfield search this
//  would mean still returning null if there are no bits set in the source mask.
//  usecase: dll_qol.QuickRaceMenu.CallbackVehicle

//------------------------------------------------------------------------------
// size conversion

pub fn KiB(comptime T: type, n: T) T {
    assert(n > 0);
    return n << 10;
}

pub fn MiB(comptime T: type, n: T) T {
    assert(n > 0);
    return n << 20;
}

pub fn GiB(comptime T: type, n: T) T {
    assert(n > 0);
    return n << 30;
}

pub fn TiB(comptime T: type, n: T) T {
    assert(n > 0);
    return n << 40;
}

test "size conversion" {
    try std.testing.expect(1024 == KiB(u64, 1));
    try std.testing.expect(10240 == KiB(u64, 10));
    try std.testing.expect(1048576 == MiB(u64, 1));
    try std.testing.expect(10485760 == MiB(u64, 10));
    try std.testing.expect(1073741824 == GiB(u64, 1));
    try std.testing.expect(10737418240 == GiB(u64, 10));
    try std.testing.expect(1099511627776 == TiB(u64, 1));
    try std.testing.expect(10995116277760 == TiB(u64, 10));
}

//------------------------------------------------------------------------------
// search functions

/// Linear search for the first index of a greater scalar value inside a slice.
pub fn indexOfScalarGreater(comptime T: type, slice: []const T, value: T) ?usize {
    return indexOfScalarGreaterPos(T, slice, 0, value);
}

/// Linear search for the first index of a greater scalar value inside a sub-slice starting at a given index.
pub fn indexOfScalarGreaterPos(comptime T: type, slice: []const T, start_index: usize, value: T) ?usize {
    for (start_index..slice.len) |i| {
        if (slice[i] > value) return i;
    }
    return null;
}

/// Linear search for the last index of a greater scalar value inside a slice.
pub fn lastIndexOfScalarGreater(comptime T: type, slice: []const T, value: T) ?usize {
    return lastIndexOfScalarGreaterPos(T, slice, slice.len, value);
}

/// Linear search for the last index of a greater scalar value inside a sub-slice ending at a given length.
pub fn lastIndexOfScalarGreaterPos(comptime T: type, slice: []const T, len: usize, value: T) ?usize {
    var i = len;
    while (i > 0) {
        i -= 1;
        if (slice[i] > value) return i;
    }
    return null;
}

test "indexOfScalarGreater" {
    const values = [2]u8{ 1, 3 };

    try std.testing.expect(0 == indexOfScalarGreater(u8, &values, 0).?);
    try std.testing.expect(1 == indexOfScalarGreater(u8, &values, 1).?);
    try std.testing.expect(1 == indexOfScalarGreater(u8, &values, 2).?);
    try std.testing.expect(null == indexOfScalarGreater(u8, &values, 3));
    try std.testing.expect(null == indexOfScalarGreater(u8, &values, 4));

    try std.testing.expect(0 == indexOfScalarGreaterPos(u8, &values, 0, 0).?);
    try std.testing.expect(1 == indexOfScalarGreaterPos(u8, &values, 1, 0).?);
    try std.testing.expect(null == indexOfScalarGreaterPos(u8, &values, 2, 0));

    try std.testing.expect(1 == lastIndexOfScalarGreater(u8, &values, 0).?);
    try std.testing.expect(1 == lastIndexOfScalarGreater(u8, &values, 1).?);
    try std.testing.expect(1 == lastIndexOfScalarGreater(u8, &values, 2).?);
    try std.testing.expect(null == lastIndexOfScalarGreater(u8, &values, 3));
    try std.testing.expect(null == lastIndexOfScalarGreater(u8, &values, 4));

    try std.testing.expect(null == lastIndexOfScalarGreaterPos(u8, &values, 0, 0));
    try std.testing.expect(0 == lastIndexOfScalarGreaterPos(u8, &values, 1, 0).?);
    try std.testing.expect(1 == lastIndexOfScalarGreaterPos(u8, &values, 2, 0).?);
}

/// Linear search for the first index of a smaller scalar value inside a slice.
pub fn indexOfScalarSmaller(comptime T: type, slice: []const T, value: T) ?usize {
    return indexOfScalarSmallerPos(T, slice, 0, value);
}

/// Linear search for the first index of a smaller scalar value inside a sub-slice starting at a given index.
pub fn indexOfScalarSmallerPos(comptime T: type, slice: []const T, start_index: usize, value: T) ?usize {
    for (start_index..slice.len) |i| {
        if (slice[i] < value) return i;
    }
    return null;
}

/// Linear search for the last index of a smaller scalar value inside a slice.
pub fn lastIndexOfScalarSmaller(comptime T: type, slice: []const T, value: T) ?usize {
    return lastIndexOfScalarSmallerPos(T, slice, slice.len, value);
}

/// Linear search for the last index of a smaller scalar value inside a sub-slice ending at a given length.
pub fn lastIndexOfScalarSmallerPos(comptime T: type, slice: []const T, len: usize, value: T) ?usize {
    var i = len;
    while (i > 0) {
        i -= 1;
        if (slice[i] < value) return i;
    }
    return null;
}

test "indexOfScalarSmaller" {
    const values = [2]u8{ 1, 3 };

    try std.testing.expect(null == indexOfScalarSmaller(u8, &values, 0));
    try std.testing.expect(null == indexOfScalarSmaller(u8, &values, 1));
    try std.testing.expect(0 == indexOfScalarSmaller(u8, &values, 2).?);
    try std.testing.expect(0 == indexOfScalarSmaller(u8, &values, 3).?);
    try std.testing.expect(0 == indexOfScalarSmaller(u8, &values, 4).?);

    try std.testing.expect(0 == indexOfScalarSmallerPos(u8, &values, 0, 4).?);
    try std.testing.expect(1 == indexOfScalarSmallerPos(u8, &values, 1, 4).?);
    try std.testing.expect(null == indexOfScalarSmallerPos(u8, &values, 2, 4));

    try std.testing.expect(null == lastIndexOfScalarSmaller(u8, &values, 0));
    try std.testing.expect(null == lastIndexOfScalarSmaller(u8, &values, 1));
    try std.testing.expect(0 == lastIndexOfScalarSmaller(u8, &values, 2).?);
    try std.testing.expect(0 == lastIndexOfScalarSmaller(u8, &values, 3).?);
    try std.testing.expect(1 == lastIndexOfScalarSmaller(u8, &values, 4).?);

    try std.testing.expect(null == lastIndexOfScalarSmallerPos(u8, &values, 0, 4));
    try std.testing.expect(0 == lastIndexOfScalarSmallerPos(u8, &values, 1, 4).?);
    try std.testing.expect(1 == lastIndexOfScalarSmallerPos(u8, &values, 2, 4).?);
}

/// Find index of first set bit greater than bit at the given index.
pub fn bitIndexOfGreater(comptime T: type, bitfield: T, index: usize) ?usize {
    assert(index < @bitSizeOf(T));
    if (index == @bitSizeOf(T) - 1) return null;
    const BitSizeT = std.meta.Int(.unsigned, std.math.log2_int_ceil(u16, @bitSizeOf(T)));
    const mask = bitfield & ~((@as(T, 1) << @as(BitSizeT, @truncate(index + 1))) - 1);
    const i = @ctz(mask);
    return if (i < @bitSizeOf(T)) i else null;
}

/// Find index of last set bit greater than bit at the given index.
pub fn lastBitIndexOfGreater(comptime T: type, bitfield: T, index: usize) ?usize {
    assert(index < @bitSizeOf(T));
    if (index == @bitSizeOf(T) - 1) return null;
    const BitSizeT = std.meta.Int(.unsigned, std.math.log2_int_ceil(u16, @bitSizeOf(T)));
    const mask = bitfield & ~((@as(T, 1) << @as(BitSizeT, @truncate(index + 1))) - 1);
    const i = @clz(mask);
    return if (i < @bitSizeOf(T)) @bitSizeOf(T) - @clz(mask) - 1 else null;
}

test "bitIndexOfGreater" {
    try std.testing.expect(2 == bitIndexOfGreater(u5, 0b10101, 0).?);
    try std.testing.expect(2 == bitIndexOfGreater(u5, 0b10101, 1).?);
    try std.testing.expect(4 == bitIndexOfGreater(u5, 0b10101, 2).?);
    try std.testing.expect(4 == bitIndexOfGreater(u5, 0b10101, 3).?);
    try std.testing.expect(null == bitIndexOfGreater(u5, 0b10101, 4));

    try std.testing.expect(null == bitIndexOfGreater(u3, 0b010, 2));
    try std.testing.expect(null == bitIndexOfGreater(u3, 0b010, 1));
    try std.testing.expect(1 == bitIndexOfGreater(u3, 0b010, 0).?);

    try std.testing.expect(4 == lastBitIndexOfGreater(u5, 0b10101, 0).?);
    try std.testing.expect(4 == lastBitIndexOfGreater(u5, 0b10101, 1).?);
    try std.testing.expect(4 == lastBitIndexOfGreater(u5, 0b10101, 2).?);
    try std.testing.expect(4 == lastBitIndexOfGreater(u5, 0b10101, 3).?);
    try std.testing.expect(null == lastBitIndexOfGreater(u5, 0b10101, 4));

    try std.testing.expect(null == lastBitIndexOfGreater(u3, 0b010, 2));
    try std.testing.expect(null == lastBitIndexOfGreater(u3, 0b010, 1));
    try std.testing.expect(1 == lastBitIndexOfGreater(u3, 0b010, 0).?);
}

/// Find index of first set bit smaller than bit at the given index.
pub fn bitIndexOfSmaller(comptime T: type, bitfield: T, index: usize) ?usize {
    assert(index < @bitSizeOf(T));
    if (index == 0) return null;
    if (bitfield == 0) return null;
    const BitSizeT = std.meta.Int(.unsigned, std.math.log2_int_ceil(u16, @bitSizeOf(T)));
    const mask = bitfield & ((@as(T, 1) << @as(BitSizeT, @truncate(index))) - 1);
    const i = @ctz(mask);
    return if (i < @bitSizeOf(T)) i else null;
}

/// Find index of first set bit smaller than bit at the given index.
pub fn lastBitIndexOfSmaller(comptime T: type, bitfield: T, index: usize) ?usize {
    assert(index < @bitSizeOf(T));
    if (index == 0) return null;
    if (bitfield == 0) return null;
    const BitSizeT = std.meta.Int(.unsigned, std.math.log2_int_ceil(u16, @bitSizeOf(T)));
    const mask = bitfield & ((@as(T, 1) << @as(BitSizeT, @truncate(index))) - 1);
    const i = @clz(mask);
    return if (i < @bitSizeOf(T)) @bitSizeOf(T) - 1 - i else null;
}

test "bitIndexOfSmaller" {
    try std.testing.expect(null == bitIndexOfSmaller(u5, 0b10101, 0));
    try std.testing.expect(0 == bitIndexOfSmaller(u5, 0b10101, 1).?);
    try std.testing.expect(0 == bitIndexOfSmaller(u5, 0b10101, 2).?);
    try std.testing.expect(0 == bitIndexOfSmaller(u5, 0b10101, 3).?);
    try std.testing.expect(0 == bitIndexOfSmaller(u5, 0b10101, 4).?);

    try std.testing.expect(null == bitIndexOfSmaller(u3, 0b010, 0));
    try std.testing.expect(null == bitIndexOfSmaller(u3, 0b010, 1));
    try std.testing.expect(1 == bitIndexOfSmaller(u3, 0b010, 2).?);

    try std.testing.expect(null == lastBitIndexOfSmaller(u5, 0b10101, 0));
    try std.testing.expect(0 == lastBitIndexOfSmaller(u5, 0b10101, 1).?);
    try std.testing.expect(0 == lastBitIndexOfSmaller(u5, 0b10101, 2).?);
    try std.testing.expect(2 == lastBitIndexOfSmaller(u5, 0b10101, 3).?);
    try std.testing.expect(2 == lastBitIndexOfSmaller(u5, 0b10101, 4).?);

    try std.testing.expect(null == lastBitIndexOfSmaller(u3, 0b010, 0));
    try std.testing.expect(null == lastBitIndexOfSmaller(u3, 0b010, 1));
    try std.testing.expect(1 == lastBitIndexOfSmaller(u3, 0b010, 2).?);
}
