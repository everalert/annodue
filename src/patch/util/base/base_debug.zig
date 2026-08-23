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

const PDBParse = @import("../debug/debug_pdbparse.zig");
const PDBLineInfo = PDBParse.LineInfo;

const rg = @import("racer").Global;

const ANNODUE_VER = @import("../../appinfo.zig").VERSION_STR;

//------------------------------------------------------------------------------
// custom panic handler

// TODO: print line contents, probably by embedding source
//  see https://andrewkelley.me/post/zig-stack-traces-kernel-panic-bare-bones-os.html
// TODO: if we normally write to file while logging, do we need to do anything extra here
//  to make it write during a crash
// TODO: revise error handling; not sure there is much point to panicking in the
//  panic handler or whatever
// TODO: decide if we need to alert user to check crashlog.txt

pub fn annodue_panic(message: []const u8, error_return_trace: ?*StackTrace, ret_addr: ?usize) noreturn {
    if (builtin.os.tag != .windows) @compileError("only windows supported");
    @setCold(true);

    // TODO: add buffered writer if possible; so far doing so caused transitive error
    const file = std.fs.cwd().createFile("annodue/crashlog.txt", .{}) catch
        @panic("failed to create crashlog.txt");
    defer file.close();
    const writer = file.writer();

    writer.print("{s}\n\n{s: <14}{s}\n{s: <14}{d}\n\n", .{
        ANNODUE_VER, "MESSAGE", message, "TIMESTAMP", std.time.milliTimestamp(),
    }) catch @panic("failed to write crashlog header");

    // TODO: take file path as input of some kind, probably by comptime function
    // TODO: print module name or pdb name or something in output (after taking
    //  such info as comptime input), to help narrow down where the panic happens
    var pdb = PDBParse.Init("annodue/annodue.pdb", null);
    defer _ = if (pdb) |pdb2| pdb2.Deinit();
    var line: PDBLineInfo = undefined;

    // TODO: start trace print at correct address; maybe just use StackIterator
    //  here if it's observed that the output is basically the same, since that
    //  seems to also include a deeper trace
    // currently starts at walkStackWindows -> annodue_panic -> stuff we're actually interested in
    blk: {
        _ = writer.write("STACK TRACE\n\n") catch break :blk;
        defer _ = writer.write("\n") catch {};
        var context: std.debug.ThreadContext = undefined;
        _ = std.debug.getContext(&context);
        var addr_buf: [1024]usize = undefined;
        const addr_n = std.debug.walkStackWindows(addr_buf[0..], &context);
        for (addr_buf[0..addr_n]) |addr| {
            if (pdb != null and pdb.?.GetLineInfo(addr, &line)) blk2: {
                _ = writer.print(
                    "0x{X:0>8}    {s: <23}  in {s}:{d}:{d}\n",
                    .{ addr, line.SymbolName[0..line.SymbolNameLen], line.FileName[0..line.FileNameLen], line.LineNumber, line.LineDisplacement },
                ) catch break :blk2;
                continue;
            }
            _ = writer.print("0x{X:0>8}    (unknown)\n", .{addr}) catch continue;
        }
    }

    // TODO: revise the necessity of this; seems to be basically the same as what
    //  stacktrace would be if it started the right address. for now, keep an eye
    //  on the output and if no variance to stacktrace is observed after a while
    //  then ditch it
    blk: {
        _ = writer.write("RETURN TRACE\n\n") catch break :blk;
        defer _ = writer.write("\n") catch {};
        var it = StackIterator.init(ret_addr orelse @returnAddress(), null);
        while (it.next()) |addr| {
            if (pdb != null and pdb.?.GetLineInfo(addr, &line)) blk2: {
                _ = writer.print(
                    "0x{X:0>8}    {s: <23}  in {s}:{d}:{d}\n",
                    .{ addr, line.SymbolName[0..line.SymbolNameLen], line.FileName[0..line.FileNameLen], line.LineNumber, line.LineDisplacement },
                ) catch break :blk2;
                continue;
            }
            _ = writer.print("0x{X:0>8}    (unknown)\n", .{addr}) catch continue;
        }
    }

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
