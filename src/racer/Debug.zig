const std = @import("std");

const w32 = @import("zigwin32");
const BOOL = w32.foundation.BOOL;

const ConsoleTextAttributesMemo: *i16 = @ptrFromInt(0x52EE7C);

pub const fnDebugConsoleSetAttributes: *const fn (attr: i16) callconv(.C) BOOL =
    @ptrFromInt(0x48D160);
pub const fnDebugConsolePrint: *const fn (str: ?[*:0]const u8, attr: i16) callconv(.C) BOOL =
    @ptrFromInt(0x48D180);
pub const fnDebugConsoleVsnprintf: *const fn (fmt: ?[*:0]const u8, ...) callconv(.C) i32 =
    @ptrFromInt(0x484820);
