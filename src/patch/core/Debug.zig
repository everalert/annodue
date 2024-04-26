const std = @import("std");
const builtin = @import("builtin");
const StackTrace = std.builtin.StackTrace;

// FIXME: make comptime-generated annodue_panic that takes a string, so that those
// piggybacking off this def aren't stuck with the annodue version str they happen
// to compile with
const ANNODUE_VER = @import("Global.zig").VersionStr;

// FIXME: should there be unreachable in here?
// TODO: if we normally write to file while logging, do we need to do anything extra here
// to make it write during a crash
pub fn annodue_panic(message: []const u8, error_return_trace: ?*StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const file = std.fs.cwd().createFile("annodue/crashlog.txt", .{}) catch unreachable;
    defer file.close();

    const head = std.fmt.allocPrint(alloc, "{s}\n{s: <16}{s}\n{s: <16}{d}\n", .{
        ANNODUE_VER,
        "MESSAGE:",
        message,
        "TIMESTAMP:",
        std.time.milliTimestamp(),
    }) catch unreachable;
    _ = file.write(head) catch unreachable;

    // TODO: get this writing things correctly, not sure if pdb needed
    // see https://andrewkelley.me/post/zig-stack-traces-kernel-panic-bare-bones-os.html
    if (comptime builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        _ = file.write("\nSTACK TRACE:\n") catch unreachable;
        var di = std.debug.DebugInfo.init(alloc) catch unreachable;
        const tty = std.io.tty.detectConfig(file);
        std.debug.writeCurrentStackTrace(file.writer(), &di, tty, @returnAddress()) catch unreachable;
    }

    _ = file.write("\nRETURN TRACE:\n") catch unreachable;
    var it = std.debug.StackIterator.init(@returnAddress(), null);
    while (it.next()) |addr| {
        const trace_str = std.fmt.allocPrint(alloc, "0x{X:0>8}\n", .{addr}) catch unreachable;
        _ = file.write(trace_str) catch unreachable;
    }

    // TODO: decide if we need to alert user to check crashlog.txt
    //msg.Message("{s}", .{global.VersionStr}, "Panic\n{s}", .{message});

    std.builtin.default_panic(message, error_return_trace, ret_addr);
}
