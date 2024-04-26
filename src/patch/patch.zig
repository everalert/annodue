const std = @import("std");
const StackTrace = std.builtin.StackTrace;

const global = @import("global.zig");
const hook = @import("hook.zig");
const allocator = @import("core/Allocator.zig");
const settings = @import("settings.zig");

const msg = @import("util/message.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

// DO THE THING!!!

export fn Init() void {
    if (!global.init()) return;

    // init

    const alloc = allocator.allocator();
    const memory = alloc.alloc(u8, patch_size) catch unreachable;
    global.GLOBAL_STATE.patch_memory = @ptrCast(memory.ptr);
    global.GLOBAL_STATE.patch_size = patch_size;
    global.GLOBAL_STATE.patch_offset = @intFromPtr(memory.ptr);

    // TODO: reimpl alloc in init fn args
    settings.init();
    hook.init();

    // debug

    if (false) {
        msg.Message("{s}", .{global.VersionStr}, "Patching SWE1R...", .{});
    }
}

export fn Deinit() void {
    // ...
}

// FIXME: should there be unreachable in here?
// TODO: if we normally write to file while logging, do we need to
pub fn panic(message: []const u8, error_return_trace: ?*StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const file = std.fs.cwd().createFile("annodue/crashlog.txt", .{}) catch unreachable;
    defer file.close();

    const head = std.fmt.allocPrint(alloc, "{s: <16}{s}\n{s: <16}{d}\n", .{
        "MESSAGE:",
        message,
        "TIMESTAMP:",
        std.time.milliTimestamp(),
    }) catch unreachable;
    _ = file.write(head) catch unreachable;

    // TODO: manually print stack trace
    // see https://andrewkelley.me/post/zig-stack-traces-kernel-panic-bare-bones-os.html
    _ = file.write("TRACE:\n") catch unreachable;

    // FIXME: possibly drop this, if it's never going to print anything useful on its own
    if (error_return_trace) |ert| {
        ert.format("", .{}, file.writer()) catch unreachable;
    } else {
        _ = file.write("No error trace.\n") catch unreachable;
    }

    // TODO: decide if we need to alert user to check crashlog.txt
    //msg.Message("{s}", .{global.VersionStr}, "Panic\n{s}", .{message});

    std.builtin.default_panic(message, error_return_trace, ret_addr);
}
