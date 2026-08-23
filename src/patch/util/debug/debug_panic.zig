const std = @import("std");
const StackIterator = std.debug.StackIterator;

const builtin = @import("builtin");
const StackTrace = std.builtin.StackTrace;

const PDBParse = @import("debug_pdbparse.zig");
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

    writer.print("{s}\n\n", .{ANNODUE_VER}) catch unreachable;
    writer.print("{s: <14}{s}\n", .{ "MESSAGE", message }) catch unreachable;
    writer.print("{s: <14}{d}\n", .{ "TIMESTAMP", std.time.milliTimestamp() }) catch unreachable;
    _ = writer.write("\n") catch unreachable;

    // TODO: take file path as input of some kind, probably by comptime function
    // TODO: print module name or pdb name or something in output (after taking
    //  such info as comptime input), to help narrow down where the panic happens
    var pdb = PDBParse.Init("annodue/annodue.pdb", null);
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
    //  then ditch it
    _ = writer.write("RETURN TRACE\n\n") catch unreachable;
    var it = StackIterator.init(ret_addr orelse @returnAddress(), null);
    while (it.next()) |addr| PrintLineInfo(&pdb, writer, addr);
    _ = writer.write("\n") catch unreachable;

    std.builtin.default_panic(message, error_return_trace, ret_addr);
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
