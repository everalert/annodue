const std = @import("std");
const assert = std.debug.assert;
const maxInt = std.math.maxInt;

pub const RGB565 = RGBModel(u5, u6, u5, u0, 11, 5, 0, 0);
pub const RGB888 = RGBModel(u8, u8, u8, u0, 16, 8, 0, 0);
pub const RGBA8888 = RGBModel(u8, u8, u8, u8, 24, 16, 8, 0);
pub const ARGB8888 = RGBModel(u8, u8, u8, u8, 16, 8, 0, 24);
pub const RGBA4444 = RGBModel(u4, u4, u4, u4, 12, 8, 4, 0);
pub const ARGB4444 = RGBModel(u4, u4, u4, u4, 8, 4, 0, 12);
pub const RGBA5551 = RGBModel(u5, u5, u5, u1, 11, 6, 1, 0);
pub const ARGB1555 = RGBModel(u5, u5, u5, u1, 10, 5, 0, 15);
pub const GA44 = RGBModel(u0, u4, u0, u4, 0, 4, 0, 0);
pub const A4 = RGBModel(u0, u0, u0, u4, 0, 0, 0, 0);

/// @Xp     position of starting bit
pub fn RGBModel(
    comptime R: type,
    comptime G: type,
    comptime B: type,
    comptime A: type,
    comptime Rp: u8,
    comptime Gp: u8,
    comptime Bp: u8,
    comptime Ap: u8,
) type {
    const total_bits = @bitSizeOf(R) + @bitSizeOf(G) + @bitSizeOf(B) + @bitSizeOf(A);
    assert(std.meta.trait.isUnsignedInt(R));
    assert(std.meta.trait.isUnsignedInt(G));
    assert(std.meta.trait.isUnsignedInt(B));
    assert(std.meta.trait.isUnsignedInt(A));
    assert(total_bits <= @bitSizeOf(usize));

    return struct {
        const T = std.meta.Int(.unsigned, total_bits);
        const RT: type = R;
        const GT: type = G;
        const BT: type = B;
        const AT: type = A;
        const RP: u8 = Rp;
        const GP: u8 = Gp;
        const BP: u8 = Bp;
        const AP: u8 = Ap;
    };
}

/// converts a color from one model to another. 0-bit RGB input channels will be
/// of value 0 in the output. if the input alpha channel is 0-bit, the output will
/// be fully opaque.
/// @Tf     from-type (ColorModel)
/// @Tt     to-type (ColorModel)
pub fn ConvertRGB(comptime Tf: anytype, comptime Tt: anytype, color: Tf.T) Tt.T {
    const ro: Tt.T = @intCast(ConvertChannel(Tf.RT, Tt.RT, (color >> Tf.RP) & maxInt(Tf.RT)));
    const go: Tt.T = @intCast(ConvertChannel(Tf.GT, Tt.GT, (color >> Tf.GP) & maxInt(Tf.GT)));
    const bo: Tt.T = @intCast(ConvertChannel(Tf.BT, Tt.BT, (color >> Tf.BP) & maxInt(Tf.BT)));
    const ao: Tt.T = if (@bitSizeOf(Tf.AT) == 0) maxInt(Tt.AT) else @intCast(ConvertChannel(Tf.AT, Tt.AT, (color >> Tf.AP) & maxInt(Tf.AT)));
    return ro << Tt.RP | go << Tt.GP | bo << Tt.BP | ao << Tt.AP;
}

test "ConvertRGB" {
    const tests = [_]struct { type, type, usize, usize }{
        .{ RGBA8888, ARGB8888, 0x4488CC00, 0x004488CC },
        .{ RGBA8888, ARGB4444, 0x4488CC00, 0x048C },
        .{ RGBA8888, ARGB1555, 0x000000FF, 0b1_00000_00000_00000 },
        .{ RGB888, ARGB8888, 0x4488CC, 0xFF4488CC },
        .{ ARGB8888, RGB888, 0x004488CC, 0x4488CC },
    };

    errdefer std.debug.print("\n", .{});
    inline for (tests, 0..) |t, i| {
        const expected: t[1].T = @intCast(t[3]);
        const input: t[0].T = @intCast(t[2]);
        const output = ConvertRGB(t[0], t[1], input);
        errdefer std.debug.print(
            "FAILED {d:0>2} :: i:{X:0>8} o:{X:0>8} e:{X:0>8}\n",
            .{ i, input, output, expected },
        );
        try std.testing.expect(output == expected);
    }
}

/// moves the green input channel into all the output color channels, "flattening"
/// the input to monochrome. the alpha channel will be used for the input and/or
/// output if the color channel/s are not available on either side. if the alpha
/// input is consumed by the output color channels, the output alpha will be fully
/// opaque. in other words, this function does a best-fit mono conversion while
/// prioritizing the color channels as the mono source. the behaviour is otherwise
/// equivalent to `ConvertRGB`. note that pre-made greyscale models will use the
/// green channel by convention.
/// @Tf     from-type (ColorRGB)
/// @Tt     to-type (ColorRGB)
pub fn ConvertMonoRGB(comptime Tf: anytype, comptime Tt: anytype, color: Tf.T) Tt.T {
    const CTf = if (@bitSizeOf(Tf.GT) > 0) Tf.GT else Tf.AT;
    const CPf = if (@bitSizeOf(Tf.GT) > 0) Tf.GP else Tf.AP;
    const CVf = (color >> CPf) & maxInt(CTf);
    const ro: Tt.T = @intCast(ConvertChannel(CTf, Tt.RT, CVf));
    const go: Tt.T = @intCast(ConvertChannel(CTf, Tt.GT, CVf));
    const bo: Tt.T = @intCast(ConvertChannel(CTf, Tt.BT, CVf));
    const ao: Tt.T = a: {
        if (@bitSizeOf(Tt.AT) == 0)
            break :a 0;
        if (@bitSizeOf(Tt.T) == @bitSizeOf(Tt.AT))
            break :a @intCast(ConvertChannel(CTf, Tt.AT, CVf));
        if (@bitSizeOf(Tf.GT) == 0 or @bitSizeOf(Tf.AT) == 0)
            break :a maxInt(Tt.AT);
        const AVf = (color >> Tf.AP) & maxInt(Tf.AT);
        break :a @intCast(ConvertChannel(Tf.AT, Tt.AT, AVf));
    };
    return ro << Tt.RP | go << Tt.GP | bo << Tt.BP | ao << Tt.AP;
}

test "ConvertMonoRGB" {
    const tests = [_]struct { type, type, usize, usize }{
        .{ GA44, A4, 0x88, 0x8 },
        .{ RGB888, A4, 0x4488CC, 0x8 },
        .{ RGBA8888, A4, 0x4488CCFF, 0x8 },
        .{ A4, GA44, 0x8, 0x8F },
        .{ RGB888, GA44, 0x4488CC, 0x8F },
        .{ RGBA8888, GA44, 0x4488CCFF, 0x8F },
        .{ A4, RGBA4444, 0x8, 0x888F },
        .{ GA44, RGBA4444, 0x88, 0x8888 },
        .{ A4, RGB888, 0x8, 0x888888 },
        .{ GA44, RGB888, 0x88, 0x888888 },
    };

    errdefer std.debug.print("\n", .{});
    inline for (tests, 0..) |t, i| {
        const expected: t[1].T = @intCast(t[3]);
        const input: t[0].T = @intCast(t[2]);
        const output = ConvertMonoRGB(t[0], t[1], input);
        errdefer std.debug.print(
            "FAILED {d:0>2} :: i:{X:0>8} o:{X:0>8} e:{X:0>8}\n",
            .{ i, input, output, expected },
        );
        try std.testing.expect(output == expected);
    }
}

/// remaps a color channel value from one bit size to another.
/// e.g. u1 (1) -> u8 (255)
/// @Tf     from-type
/// @Tt     to-type
pub inline fn ConvertChannel(comptime Tf: type, comptime Tt: type, n: usize) Tt {
    assert(std.meta.trait.isUnsignedInt(Tf));
    assert(std.meta.trait.isUnsignedInt(Tt));
    assert(@bitSizeOf(Tf) + @bitSizeOf(Tt) <= @bitSizeOf(usize));
    if (@bitSizeOf(Tf) == 0 or @bitSizeOf(Tt) == 0) return 0;
    return @intCast(n * maxInt(Tt) / maxInt(Tf));
}

test "ConvertChannel" {
    const tests = [_]struct { type, type, usize, usize }{
        .{ u1, u8, 0x01, 0xFF },
        .{ u8, u1, 0xFF, 0x01 },
        .{ u8, u1, 0xFE, 0x00 },
    };

    errdefer std.debug.print("\n", .{});
    inline for (tests, 0..) |t, i| {
        const expected: t[1] = @intCast(t[3]);
        const input: t[0] = @intCast(t[2]);
        const output = ConvertChannel(t[0], t[1], input);
        errdefer std.debug.print(
            "FAILED {d:0>2} :: i:{X:0>8} o:{X:0>8} e:{X:0>8}\n",
            .{ i, input, output, expected },
        );
        try std.testing.expect(output == expected);
    }
}
