const Self = @This();

const std = @import("std");

const r = @import("racer.zig");
const rf = @import("racer_fn.zig");
const rc = @import("racer_const.zig");

const msg = @import("message.zig");

// NOTE: original idea notes
// swrText_CreateEntry helper ideas
//
// general
// - shorthand for pos, color
//
// 1
// - interface similar to messagebox helper for CreateEntry caller, that handles
//   the buf etc.
// - separate struct that defines a format and can be converted to a string, which
//   can be used as a string arg
// - CreateEntry caller maybe take one such struct as an arg just for the initial
//   formatting?
//
// 2
// - a "builder" type interface
// - struct type to define a format
// - union type that is either a string or a format def
// - a builder function for the CreateEntry call, which takes an array of such
//   union types and generates the formatted string
//
// 3
// - an api that lets you do both ways, with overlapping ideas homogenized

pub const DEFAULT_STYLE: []const u8 = "~F0~s";

pub const DEFAULT_COLOR: u32 = 0xFFFFFFBE; // 255, 255, 255, 190

pub const Color = enum(u8) {
    Black = 0,
    White = 1,
    Blue = 2,
    Yellow = 3,
    Green = 4,
    Red = 5,
    Brown = 6,
    Gray = 7,
    Pink = 8,
    Purple = 9,
};

pub const ColorRGB = enum(u32) {
    Black = 0x000000,
    White = 0xFFFFFF,
    Blue = 0x6EB4FF,
    Yellow = 0xFFFF9C,
    Green = 0x96FF96,
    Red = 0xFF6450,
    Brown = 0xBC865E,
    Indigo = 0x6E6E80,
    Pink = 0xFFA7D1,
    Purple = 0x985EFF,

    pub fn rgba(self: *const ColorRGB, a: u8) u32 {
        return (@intFromEnum(self.*) << 8) | a;
    }

    pub fn get(color: Color) ColorRGB {
        return std.enums.values(ColorRGB)[@intFromEnum(color)];
    }
};

pub const Font = enum(u8) {
    Default,
    Unk2,
    Unk3,
    Unk4,
    Small,
    Unk6,
    Unk7,
};

pub const Alignment = enum(u8) { Center, Right };

pub const TextStyleOpts = enum(u8) {
    ClearDecoration, // ~p
    ToggleOutlineLight, // ~k
    ToggleOutlineHeavy, // ~o
    ToggleShadow, // ~s
    CutRemainingText, // ~b
    // ~~ (unk)
    // ~t (unk)
    // ~n (unk)
};

// TODO: not inline
pub inline fn MakeTextHeadStyle(font: Font, font_hires: bool, color: ?Color, alignment: ?Alignment, opts: anytype) ![]const u8 {
    var buf: [28]u8 = undefined;

    _ = try std.fmt.bufPrint(&buf, "~{s}{d}", .{
        if (font_hires) "F" else "f",
        @intFromEnum(font),
    });

    const style = comptime try MakeTextStyle(color, alignment, opts);
    _ = try std.fmt.bufPrint(buf[3..], style, .{});

    return buf[0 .. 3 + style.len];
}

// TODO: not inline
pub inline fn MakeTextStyle(color: ?Color, alignment: ?Alignment, opts: anytype) ![]const u8 {
    var buf: [24]u8 = undefined;
    var i: u32 = 0;

    const co = if (color) |c| try std.fmt.bufPrint(buf[i..], "~{d}", .{@intFromEnum(c)}) else "";
    i += co.len;

    const ao = if (alignment) |a| try std.fmt.bufPrint(buf[i..], switch (a) {
        .Center => "~c",
        .Right => "~r",
    }, .{}) else "";
    i += ao.len;

    const OptsType = @TypeOf(opts);
    const opts_type_info = @typeInfo(OptsType);
    if (opts_type_info != .Struct)
        @compileError("expected tuple or struct, found " ++ @typeName(OptsType));

    const opts_len = opts_type_info.Struct.fields.len;
    if (opts_len > 8)
        @compileError("8 opts max supported per call");

    inline for (0..opts_len) |opts_i| {
        if (@TypeOf(opts[opts_i]) != TextStyleOpts)
            @compileError("all opts members must be " ++ @typeName(TextStyleOpts));

        const oo = try std.fmt.bufPrint(buf[i..], switch (opts[opts_i]) {
            .ClearDecoration => "~p",
            .ToggleOutlineLight => "~k",
            .ToggleOutlineHeavy => "~o",
            .ToggleShadow => "~s",
            .CutRemainingText => "~b",
        }, .{});
        i += oo.len;
    }

    buf[i] = 0;
    return buf[0..i];
}

pub fn DrawText(x: i16, y: i16, comptime fmt: []const u8, args: anytype, rgba: ?u32, style: ?[]const u8) !void {
    const state = struct {
        var buf1: [127:0]u8 = undefined;
        var buf2: [127:0]u8 = undefined;
    };
    const color: u32 = rgba orelse DEFAULT_COLOR;
    const head: []const u8 = style orelse DEFAULT_STYLE;
    const body = try std.fmt.bufPrintZ(state.buf1[head.len..], fmt, args);
    _ = try std.fmt.bufPrintZ(&state.buf2, "{s}{s}", .{ head, body });
    rf.swrText_CreateEntry1(
        x,
        y,
        @as(u8, @truncate(color >> 24)),
        @as(u8, @truncate(color >> 16)),
        @as(u8, @truncate(color >> 8)),
        @as(u8, @truncate(color >> 0)),
        &state.buf2,
    );
}
