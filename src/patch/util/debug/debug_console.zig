const std = @import("std");

const w32 = @import("zigwin32");
const w32wm = w32.ui.windows_and_messaging;
const HANDLE = w32.foundation.HANDLE;
const HWND = w32.foundation.HWND;
const GetStdHandle = w32.system.console.GetStdHandle;
const AllocConsole = w32.system.console.AllocConsole;
const GetConsoleWindow = w32.system.console.GetConsoleWindow;
const WriteConsoleA = w32.system.console.WriteConsoleA;

// FIXME: remove this and use win32 function to get process handle
const rg = @import("racer").Global;

const ANNODUE_VER = @import("../../appinfo.zig").VERSION_STR;

const DebugConsole = struct {
    var initialized: bool = false;
    var handle_out: HANDLE = undefined;
    var hwnd: ?HWND = null;
};

// NOTE: lazy loaded console alloc because comptime optimize mode checking was
// removed in 0.11.0; consider changing to checking for debug build when it's back

fn Init() void {
    if (DebugConsole.initialized) return;

    _ = AllocConsole();
    DebugConsole.handle_out = GetStdHandle(.OUTPUT_HANDLE);
    DebugConsole.hwnd = GetConsoleWindow();
    DebugConsole.initialized = true;

    _ = w32wm.SetWindowPos(DebugConsole.hwnd, null, 0, 0, 640, 960, .{});
    _ = w32wm.SetForegroundWindow(@ptrCast(rg.WINDOW_HWND.*));
}

fn WriteConsole(handle: HANDLE, comptime fmt: []const u8, args: anytype) !void {
    const len = @as(usize, @truncate(std.fmt.count(fmt, args)));
    var buf: [1024]u8 = undefined;
    const out = try std.fmt.bufPrint(&buf, fmt, args);
    _ = WriteConsoleA(handle, @ptrCast(&out[0]), len, null, null);
}

pub fn ConsoleOut(comptime fmt: []const u8, args: anytype) !void {
    if (!DebugConsole.initialized) {
        Init();
        try WriteConsole(DebugConsole.handle_out, "{s}\n\n", .{ANNODUE_VER});
    }
    try WriteConsole(DebugConsole.handle_out, fmt, args);
}
