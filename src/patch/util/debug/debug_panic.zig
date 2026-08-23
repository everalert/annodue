//! custom panic handler for annodue
//!
//! manually processes a given .pdb live for debug symbols, to ensure the stacktrace
//! is actually readable.
//!
//! the reason we need this is because of two factors specific to our project that
//! make the debug info unreliable:
//!   1) we are loading a dll into a hooked process, and this scenario specifically
//!      seems to mess with acquisition more than usual with zig and pdb files
//!   2) we want to be able to generate a stacktrace in release builds (at least
//!      until 1.0.0), where the debug info and source are simply not available
//!      where the exe expects them to be
//!
//! use by placing a definition similar to the following in the module root:
//! `pub const panic = debug_panic.PanicFromContext(module_name, pdb_path.pdb);`
//!
//! pdb_path must be the path where the .pdb will be found relative to the game
//! exe, usually in the annodue folder (although you could use this generically)
const Panic = @This();

// TODO: print line contents, probably by embedding source
//  see https://andrewkelley.me/post/zig-stack-traces-kernel-panic-bare-bones-os.html
// TODO: if we normally write to file for normal logs, do we need to do anything
//  extra here to make it write during a crash?
// TODO: revise error handling; not sure there is much point to panicking in the
//  panic handler or whatever
// TODO: decide if we need to alert user to check crashlog.txt
// TODO: "dynamic" annodue folder path for crashlog based on some def in
//  libannodue (or maybe also self-defined, for full decoupling from annodue)

const std = @import("std");
const builtin = @import("builtin");
const StackIterator = std.debug.StackIterator;
const StackTrace = std.builtin.StackTrace;

const PDBParse = @import("debug_pdbparse.zig");
const PDBLineInfo = PDBParse.LineInfo;

const ANNODUE_VER = @import("../../appinfo.zig").VERSION_STR;

const PanicFnT = @TypeOf(std.builtin.default_panic);

pub fn PanicFromContext(comptime name: [:0]const u8, comptime path: [:0]const u8) PanicFnT {
    const MODULE_NAME = name;
    const MODULE_PATH = path;

    const s = struct {
        fn AnnoduePanic(message: []const u8, error_return_trace: ?*StackTrace, ret_addr: ?usize) noreturn {
            if (builtin.os.tag != .windows) @compileError("only windows supported");
            @setCold(true);

            // TODO: add buffered writer if possible; so far doing so caused transitive error
            const file = std.fs.cwd().createFile("annodue/crashlog.txt", .{}) catch
                @panic("failed to create crashlog.txt");
            defer file.close();
            const writer = file.writer();

            writer.print("{s}\n\n", .{ANNODUE_VER}) catch unreachable;
            writer.print("{s: <14}{d}\n", .{ "TIMESTAMP", std.time.milliTimestamp() }) catch unreachable;
            writer.print("{s: <14}{s}\n", .{ "MODULE", MODULE_NAME }) catch unreachable;
            writer.print("{s: <14}{s}\n", .{ "MESSAGE", message }) catch unreachable;
            _ = writer.write("\n") catch unreachable;

            // TODO: take file path as input of some kind, probably by comptime function
            // TODO: print module name or pdb name or something in output (after taking
            //  such info as comptime input), to help narrow down where the panic happens
            var pdb = PDBParse.Init(MODULE_PATH, null);
            defer _ = if (pdb) |*pdb2| pdb2.Deinit();

            // TODO: start trace print at correct address; maybe just use StackIterator
            //  here if it's observed that the output is basically the same, since that
            //  seems to also include a deeper trace
            // currently starts at walkStackWindows -> annodue_panic -> stuff we're actually interested in
            _ = writer.write("STACK TRACE\n\n") catch unreachable;
            var context: std.debug.ThreadContext = undefined;
            _ = std.debug.getContext(&context);
            var addr_buf: [1024]usize = undefined;
            const addr_n = std.debug.walkStackWindows(addr_buf[0..], &context);
            for (addr_buf[0..addr_n]) |addr| PrintLineInfo(&pdb, writer, addr);
            _ = writer.write("\n") catch unreachable;

            // TODO: revise the necessity of this; seems to be basically the same as what
            //  stacktrace would be if it started the right address. for now, keep an eye
            //  on the output and if no variance to stacktrace is observed after a while
            //  then ditch it. also maybe peep the StackIterator impl and compare with
            //  what writeStackTraceWindows does
            _ = writer.write("RETURN TRACE\n\n") catch unreachable;
            var it = StackIterator.init(ret_addr orelse @returnAddress(), null);
            while (it.next()) |addr| PrintLineInfo(&pdb, writer, addr);
            _ = writer.write("\n") catch unreachable;

            std.builtin.default_panic(message, error_return_trace, ret_addr);
        }
    };

    return s.AnnoduePanic;
}

fn PrintLineInfo(pdb: *const ?PDBParse, writer: anytype, addr: usize) void {
    var line: PDBLineInfo = undefined;
    if (pdb.* != null and pdb.*.?.GetLineInfo(addr, &line)) blk: {
        _ = writer.print(
            "0x{X:0>8}    {s: <23}  in {s}:{d}:{d}\n",
            .{
                addr,
                line.SymbolName[0..line.SymbolNameLen],
                line.FileName[0..line.FileNameLen],
                line.LineNumber,
                line.LineDisplacement,
            },
        ) catch break :blk;
        return;
    }
    _ = writer.print("0x{X:0>8}    (unknown)\n", .{addr}) catch unreachable;
}
