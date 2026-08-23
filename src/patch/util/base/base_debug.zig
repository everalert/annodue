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
    if (builtin.os.tag != .windows) @compileError("only windows supported");
    @setCold(true);

    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    _ = alloc;

    const file = std.fs.cwd().createFile("annodue/crashlog.txt", .{}) catch
        @panic("failed to create crashlog.txt");
    defer file.close();
    const writer = file.writer();
    // TODO: add buffered writer if possible; using below code and changing write
    // references to use "file_w" causes transitive error during compilation
    //var file_bw = std.io.bufferedWriter(file.writer());
    //defer file_bw.flush();
    //var file_w = file_bw.writer();

    writer.print("{s}\n\n{s: <16}{s}\n{s: <16}{d}\n\n", .{
        ANNODUE_VER, "MESSAGE:", message, "TIMESTAMP:", std.time.milliTimestamp(),
    }) catch @panic("failed to write crashlog header");

    // TODO: switch on whether or not debug info is stripped, not build mode
    // TODO: get this writing things correctly, not sure if pdb needed
    // see https://andrewkelley.me/post/zig-stack-traces-kernel-panic-bare-bones-os.html
    //if (comptime (builtin.mode == .Debug or builtin.mode == .ReleaseSafe)) {
    //    _ = writer.write("\nSTACK TRACE\n") catch @panic("failed to write crashlog stack trace header");
    //    var di = DebugInfo.init(alloc) catch @panic("failed to init debuginfo during panic");
    //    const tty = std.io.tty.detectConfig(file);
    //    std.debug.writeCurrentStackTrace(writer, &di, tty, ret_addr orelse @returnAddress) catch
    //        @panic("failed to write stack trace to crashlog");
    //}
    blk: {
        _ = writer.write("STACK TRACE\n\n") catch break :blk;
        defer _ = writer.write("\n") catch {};
        var context: std.debug.ThreadContext = undefined;
        _ = std.debug.getContext(&context);
        var addr_buf: [1024]usize = undefined;
        const addr_n = std.debug.walkStackWindows(addr_buf[0..], &context);
        for (addr_buf[0..addr_n]) |addr|
            writer.print("0x{X:0>8}\n", .{addr}) catch break :blk;
    }

    blk: {
        _ = writer.write("RETURN TRACE\n\n") catch break :blk;
        defer _ = writer.write("\n") catch {};
        var it = StackIterator.init(ret_addr orelse @returnAddress(), null);
        while (it.next()) |addr|
            writer.print("0x{X:0>8}\n", .{addr}) catch break :blk;
    }

    // TODO: decide if we need to alert user to check crashlog.txt
    //msg.Message("{s}", .{global.VersionStr}, "Panic\n{s}", .{message});

    std.builtin.default_panic(message, error_return_trace, ret_addr);
}

// NOTE: output style experimentation
//Annodue 0.1.6.573
//
//MESSAGE:        panic test
//TIMESTAMP:      1787436603326
//
//STACK TRACE
//
//<filepath>:<symbol_name>(L<line>) 0x6584AF16+0x20/0x4C(42%)
//<filepath>:<symbol_name>(L<line>) 0x65831AA5+0x20/0x4C(42%)
//<filepath>:<symbol_name>(L<line>) 0x658426AF+0x20/0x4C(42%)
//<filepath>:<symbol_name>(L<line>) 0x6588F825+0x20/0x4C(42%)
//
//RETURN TRACE
//
//<filepath>:<symbol_name>@0x658426AF+0x20/0x4C(42%)
//<filepath>:<symbol_name>@0x6588F825+0x20/0x4C(42%)
//<filepath>:<symbol_name>@0x18B5816A+0x20/0x4C(42%)
//<filepath>:<symbol_name>@0x084D8BEC+0x20/0x4C(42%)
//
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig: RegIndex @ 0x4CE080(+0x08/0x15:38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig: RegIndex @ 0x4CE080(+38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig(248): RegIndex @ 0x4CE080(+38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248: RegIndex @ 0x4CE080(+38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248: RegIndex @ 0x4CE080(+0x08:38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248: RegIndex @ 0x4CE080+0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig(248): RegIndex @ 0x4CE080+0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:L248: RegIndex @ 0x4CE080+0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig: RegIndex @ 248:0x4CE080+0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:0x4CE080+0x08(38%): RegIndex
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248+???:0x4CE080+0x08(38%): RegIndex
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig in RegIndex@248 :: 0x4CE080+0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig in RegIndex(248) :: 0x4CE080+0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248: RegIndex at 0x4CE080+0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248: 0x4CE080 + 0x08(38%) in RegIndex
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248: RegIndex at 0x4CE080 + 0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:RegIndex at 0x4CE080+0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248: RegIndex at 0x4CE080+0x08(38%)
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248: 0x4CE080+0x08(38%) in RegIndex
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248: 0x4CE088 in RegIndex(38%)
//0x4CE088 RegIndex in F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:16
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:16: 0x4CE088 in RegIndex
//0x4CE088: F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:16 in RegIndex
//(0x4CE088) F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:16 in RegIndex
//0x4CE088 in RegIndex at F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:16
//[0x4CE088] RegIndex @ F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:16
//(0x4CE088) RegIndex @ F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:16
//0x4CE088  RegIndex at F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig:248:16
//
//4CE080
//21
//SymTagFunction
//RegIndex
//F:\Projects\swe1r\annodue\code\src\patch\util\x86.zig
//248

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

//------------------------------------------------------------------------------
// new (unorganized) stuff

const GetModuleHandleExA = w32.system.library_loader.GetModuleHandleExA;
const FLAG_FROM_ADDRESS = w32.system.library_loader.GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS;
const FLAG_UNCHANGED_REFCOUNT = w32.system.library_loader.GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT;
const HINSTANCE = w32.foundation.HINSTANCE;
const FALSE = w32.zig.FALSE;

/// get base address of windows module executing this function. returns 0 if
/// unable to get address.
pub inline fn ModuleBaseAddress() usize {
    return ModuleBaseAddressFrom(@intFromPtr(&ModuleBaseAddressFrom));
}

/// get base address of windows module to which @src_address belongs. returns 0 if
/// unable to get address.
///  - to get the address of the currently-executing module, use `ModuleBaseAddress`
///  - to get the address of an undefined calling module (e.g. a parent DLL in a DLL
///    loading chain), pass @returnAddress into this function from an export function.
pub fn ModuleBaseAddressFrom(src_address: usize) usize {
    var hmod: ?HINSTANCE = null;
    const flags = FLAG_FROM_ADDRESS | FLAG_UNCHANGED_REFCOUNT;
    _ = GetModuleHandleExA(flags, @ptrFromInt(src_address), &hmod);
    return if (hmod) |h| @intFromPtr(h) else 0;
}
