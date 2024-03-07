pub const Self = @This();

const std = @import("std");

const user32 = std.os.windows.user32;
const MessageBoxA = user32.MessageBoxA;
const MB_OK = user32.MB_OK;
const MB_ICONINFORMATION = user32.MB_ICONINFORMATION;

pub fn Message(comptime fmt_t: []const u8, args_t: anytype, comptime fmt_m: []const u8, args_m: anytype) void {
    var buf_t: [2047:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf_t, fmt_t, args_t) catch return;
    var buf_m: [2047:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf_m, fmt_m, args_m) catch return;
    _ = MessageBoxA(null, &buf_m, &buf_t, MB_OK);
}

pub fn TestMessage(comptime fmt: []const u8, args: anytype) void {
    var buf: [2047:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, fmt, args) catch return;
    _ = MessageBoxA(null, &buf, "annodue.dll", MB_OK);
}

pub fn ErrMessage(label: []const u8, err: anyerror) void {
    TestMessage("[ERROR] {s}: {s}", .{ label, @errorName(err) });
}

pub fn PtrMessage(label: []const u8, ptr: usize) void {
    TestMessage("{s}: 0x{s}", .{ label, ptr });
}
