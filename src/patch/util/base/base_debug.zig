const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const DebugInfo = std.debug.DebugInfo;
const StackIterator = std.debug.StackIterator;

const builtin = @import("builtin");
const StackTrace = std.builtin.StackTrace;

const w32 = @import("zigwin32");
const w32wm = w32.ui.windows_and_messaging;
const HANDLE = w32.foundation.HANDLE;
const HWND = w32.foundation.HWND;
const GetStdHandle = w32.system.console.GetStdHandle;
const AllocConsole = w32.system.console.AllocConsole;
const GetConsoleWindow = w32.system.console.GetConsoleWindow;
const WriteConsoleA = w32.system.console.WriteConsoleA;

const rg = @import("racer").Global;

const ANNODUE_VER = @import("../../appinfo.zig").VERSION_STR;

//------------------------------------------------------------------------------
// custom panic handler
// TODO: integrate custom pdb parser that holds pdb data in memory

// FIXME: should there be unreachable in here?
// TODO: if we normally write to file while logging, do we need to do anything extra here
// to make it write during a crash
pub fn annodue_panic(message: []const u8, error_return_trace: ?*StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const file = std.fs.cwd().createFile("annodue/crashlog.txt", .{}) catch
        @panic("failed to create crashlog.txt");
    defer file.close();
    // TODO: add buffered writer if possible; using below code and changing write
    // references to use "file_w" causes transitive error during compilation
    //var file_bw = std.io.bufferedWriter(file.writer());
    //defer file_bw.flush();
    //var file_w = file_bw.writer();

    const head = std.fmt.allocPrint(alloc, "{s}\n{s: <16}{s}\n{s: <16}{d}\n", .{
        ANNODUE_VER, "MESSAGE:", message, "TIMESTAMP:", std.time.milliTimestamp(),
    }) catch @panic("failed to format crashlog header");
    _ = file.write(head) catch
        @panic("failed to write crashlog header");

    // TODO: get this writing things correctly, not sure if pdb needed
    // see https://andrewkelley.me/post/zig-stack-traces-kernel-panic-bare-bones-os.html
    if (comptime builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        _ = file.write("\nSTACK TRACE:\n") catch
            @panic("failed to write crashlog stack trace header");
        var di = DebugInfo.init(alloc) catch
            @panic("failed to init debuginfo during panic");
        const tty = std.io.tty.detectConfig(file);
        std.debug.writeCurrentStackTrace(file.writer(), &di, tty, @returnAddress()) catch
            @panic("failed to write stack trace to crashlog");
    }

    _ = file.write("\nRETURN TRACE:\n") catch
        @panic("failed to write crashlog return trace header");
    var it = StackIterator.init(@returnAddress(), null);
    while (it.next()) |addr| {
        const trace_str = std.fmt.allocPrint(alloc, "0x{X:0>8}\n", .{addr}) catch
            @panic("failed to format crashlog return trace address");
        _ = file.write(trace_str) catch
            @panic("failed to write return trace address to crashlog");
    }

    // TODO: decide if we need to alert user to check crashlog.txt
    //msg.Message("{s}", .{global.VersionStr}, "Panic\n{s}", .{message});

    std.builtin.default_panic(message, error_return_trace, ret_addr);
}

//------------------------------------------------------------------------------
// NOTE: migrated from old util/debug.zig
// TODO: ?? possibly reorganize this and above into separate files, maybe under
//  debug category instead of base?

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

pub inline fn PPanic(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [2048]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, fmt, args) catch @panic(fmt);
    @panic(out);
}

pub inline fn PCompileError(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [2048]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, fmt, args) catch @compileError(fmt);
    @compileError(out);
}
