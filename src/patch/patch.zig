const std = @import("std");

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

export fn Patch() void {
    const alloc = allocator.allocator();
    const memory = alloc.alloc(u8, patch_size) catch unreachable;
    var off: usize = @intFromPtr(memory.ptr);

    // init

    global.GLOBAL_STATE.patch_memory = @ptrCast(memory.ptr);
    global.GLOBAL_STATE.patch_size = patch_size;

    // FIXME: cleanup all the redundant 'off' in this path
    global.GLOBAL_STATE.patch_offset = off;
    global.init();
    settings.init();
    off = hook.init(off);

    // debug

    if (false) {
        msg.Message("{s}", .{global.VersionStr}, "Patching SWE1R...", .{});
    }
}
