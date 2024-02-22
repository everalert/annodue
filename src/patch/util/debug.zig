const std = @import("std");
const win = std.os.windows;
const win32 = @import("../import/import.zig").win32;
const win32c = win32.system.console;

const global = @import("../global.zig");

const DebugConsole = struct {
    var initialized: bool = false;
    var handle_out: win.HANDLE = undefined;
};

// NOTE: lazy loaded console alloc because comptime optimize mode checking was
// removed in 0.11.0; consider changing to checking for debug build when it's back

// FIXME: actual styling of the debug window
// FIXME: also returning focus to the game on instantiation automatically
fn Init() void {
    if (DebugConsole.initialized) return;

    _ = win32c.AllocConsole();
    DebugConsole.handle_out = win32c.GetStdHandle(.OUTPUT_HANDLE);
    DebugConsole.initialized = true;
}

fn WriteConsole(handle: win.HANDLE, comptime fmt: []const u8, args: anytype) !void {
    const len = @as(usize, @truncate(std.fmt.count(fmt, args)));
    var buf: [1024]u8 = undefined;
    const out = try std.fmt.bufPrint(&buf, fmt, args);
    _ = win32c.WriteConsoleA(handle, @ptrCast(&out[0]), len, null, null);
}

pub fn ConsoleOut(comptime fmt: []const u8, args: anytype) !void {
    if (!DebugConsole.initialized) {
        Init();
        try WriteConsole(DebugConsole.handle_out, "{s}\n\n", .{global.VersionStr});
    }
    try WriteConsole(DebugConsole.handle_out, fmt, args);
}
