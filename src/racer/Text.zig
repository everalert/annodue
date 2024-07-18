const Self = @This();

const std = @import("std");

// TODO: merge with Quad

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

// GAME FUNCTIONS

pub const swrText_CreateEntry: *fn (x: i16, y: i16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8, font: i32, entry2: u32) callconv(.C) void = @ptrFromInt(0x4503E0);
pub const swrText_CreateEntry1: *fn (x: i16, y: i16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x450530);
pub const swrText_CreateEntry2: *fn (x: i16, y: i16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x4505C0);
pub const swrText_DrawTime2: *fn (x: i16, y: i16, time: f32, r: u8, g: u8, b: u8, a: u8, prefix: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x450670);
pub const swrText_DrawTime3: *fn (x: i16, y: i16, time: f32, r: u8, g: u8, b: u8, a: u8, prefix: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x450760);
pub const swrText_NewNotification: *fn (str: [*:0]const u8, duration: f32) callconv(.C) void = @ptrFromInt(0x44FCE0);

pub const RenderSetColor: *fn (r: u8, g: u8, b: u8, a: u8) callconv(.C) void = @ptrFromInt(0x42D950);
pub const RenderSetPosition: *fn (x: i16, y: i16) callconv(.C) void = @ptrFromInt(0x42D910);
pub const RenderString: *fn (str: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x42EC50);

pub const GetStringWidthByFontIndex: *fn (str: [*:0]const u8, font: u32) callconv(.C) i32 =
    @ptrFromInt(0x42DE10);
pub const GetStringWidth: *fn (str: [*:0]const u8, font: *anyopaque) callconv(.C) i32 =
    @ptrFromInt(0x42DE30);
pub const GetStringHeight: *fn (str: [*:0]const u8, font: *anyopaque) callconv(.C) i32 =
    @ptrFromInt(0x42DF70);
pub const SetCurrentFont: *fn (index: u32) callconv(.C) void =
    @ptrFromInt(0x42D8D0);

// GAME CONSTANTS

pub const TEXT_COLOR_PRESET = [10]u32{
    0x000000, // (black)
    0xFFFFFF, // (white)
    0x6EB4FF, // (blue)
    0xFFFF9C, // (yellow)
    0x96FF96, // (green)
    0xFF6450, // (red)
    0xBC865E, // (brown)
    0x6E6E80, // (gray)
    0xFFA7D1, // (pink)
    0x985EFF, // (purple)
};

pub const TEXT_HIRES_FLAG_ADDR: usize = 0x50C0AC;
pub const TEXT_HIRES_FLAG: *u32 = @ptrFromInt(TEXT_HIRES_FLAG_ADDR);

// TODO: font typedef (probably sprite?)
pub const TEXT_FONT_CURRENT_ADDR: usize = 0x50C0C4;
pub const TEXT_FONT_CURRENT: **anyopaque = @ptrFromInt(TEXT_FONT_CURRENT_ADDR);
pub const TEXT_FONT_NUM_ADDR: usize = 0x50C0C0;
pub const TEXT_FONT_NUM: *u32 = @ptrFromInt(TEXT_FONT_NUM_ADDR);
pub const TEXT_FONT_TABLE_ADDR: usize = 0xE99720;
pub const TEXT_FONT_TABLE: *[*]*anyopaque = @ptrFromInt(TEXT_FONT_TABLE_ADDR);

// HELPERS

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
    Gray = 0x6E6E80,
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

pub const Alignment = enum(u8) { Left, Center, Right };

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
        else => "",
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

// TODO: assert/test sizeof = 1024 bytes
pub const TextDef = extern struct {
    x: i16,
    y: i16,
    color: u32, // alpha 0 = default color (i.e. 0 = no color)
    string: [1015:0]u8, // fit to 64-byte cache line boundary
};

/// format text in racer format, without forwarding to the engine for rendering
/// result must be used before the next MakeText call, as the pointer will become stale quickly
pub fn MakeText(x: i16, y: i16, comptime fmt: []const u8, args: anytype, rgba: ?u32, style: ?[]const u8) !*TextDef {
    const state = struct {
        var buf: [1015:0]u8 = undefined;
        var data: TextDef = std.mem.zeroes(TextDef);
    };
    state.data.x = x;
    state.data.y = y;
    state.data.color = rgba orelse DEFAULT_COLOR;
    const head: []const u8 = style orelse DEFAULT_STYLE;
    const body = try std.fmt.bufPrintZ(state.buf[head.len..], fmt, args);
    _ = try std.fmt.bufPrintZ(&state.data.string, "{s}{s}", .{ head, body });

    return &state.data;
}

/// format text in racer format, and send to engine text render queue
/// resulting string must be within 127 characters to fit into engine buffer
pub fn DrawText(x: i16, y: i16, comptime fmt: []const u8, args: anytype, rgba: ?u32, style: ?[]const u8) !void {
    const text = try MakeText(x, y, fmt, args, rgba, style);
    std.debug.assert(std.mem.len(@as([*:0]u8, @ptrCast(&text.string))) <= 127);
    swrText_CreateEntry1(
        text.x,
        text.y,
        @as(u8, @truncate(text.color >> 24)),
        @as(u8, @truncate(text.color >> 16)),
        @as(u8, @truncate(text.color >> 8)),
        @as(u8, @truncate(text.color >> 0)),
        &text.string,
    );
}

pub fn TextGetFontIndex(str: [*:0]const u8) u32 {
    var i: u32 = 0;
    while (str[i] != 0) : (i += 1) {
        if (str[i] == '~' and (str[i + 1] == 'f' or str[i + 1] == 'F'))
            return std.math.clamp(str[i + 2] - '0', 0, TEXT_FONT_NUM.* - 1);
    }
    return 0;
}

pub fn TextGetAlignment(str: [*:0]const u8) Alignment {
    var i: u32 = 0;
    while (str[i] != 0) : (i += 1) {
        if (str[i] == '~' and str[i + 1] == 'c')
            return .Center;
        if (str[i] == '~' and str[i + 1] == 'r')
            return .Right;
    }
    return .Left;
}

pub fn TextGetDimensions(str: [*:0]const u8) struct { w: i16, h: i16 } {
    const font_idx = TextGetFontIndex(str);
    const font = TEXT_FONT_TABLE.*[font_idx];
    return .{
        .w = @truncate(GetStringWidth(str, font)), // FIXME: crash
        .h = @truncate(GetStringHeight(str, font)), // FIXME: crash
    };
}
