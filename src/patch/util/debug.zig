const std = @import("std");

const win = std.os.windows;
const w32 = @import("zigwin32");
const w32f = w32.foundation;
const w32c = w32.system.console;
const w32wm = w32.ui.windows_and_messaging;

const global = @import("../core/Global.zig");
const mem = @import("memory.zig");
const rc = @import("racer.zig").constants;

const DebugConsole = struct {
    var initialized: bool = false;
    var handle_out: w32f.HANDLE = undefined;
    var hwnd: ?w32f.HWND = null;
};

// NOTE: lazy loaded console alloc because comptime optimize mode checking was
// removed in 0.11.0; consider changing to checking for debug build when it's back

fn Init() void {
    if (DebugConsole.initialized) return;

    _ = w32c.AllocConsole();
    DebugConsole.handle_out = w32c.GetStdHandle(.OUTPUT_HANDLE);
    DebugConsole.hwnd = w32c.GetConsoleWindow();
    DebugConsole.initialized = true;

    _ = w32wm.SetWindowPos(DebugConsole.hwnd, null, 0, 0, 640, 960, .{});
    _ = w32wm.SetForegroundWindow(mem.read(rc.ADDR_HWND, w32f.HWND));
}

fn WriteConsole(handle: win.HANDLE, comptime fmt: []const u8, args: anytype) !void {
    const len = @as(usize, @truncate(std.fmt.count(fmt, args)));
    var buf: [1024]u8 = undefined;
    const out = try std.fmt.bufPrint(&buf, fmt, args);
    _ = w32c.WriteConsoleA(handle, @ptrCast(&out[0]), len, null, null);
}

pub fn ConsoleOut(comptime fmt: []const u8, args: anytype) !void {
    if (!DebugConsole.initialized) {
        Init();
        try WriteConsole(DebugConsole.handle_out, "{s}\n\n", .{global.VersionStr});
    }
    try WriteConsole(DebugConsole.handle_out, fmt, args);
}
