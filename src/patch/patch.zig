const std = @import("std");

const hooking = @import("hook.zig");
const settings = @import("settings.zig");
const global = @import("global.zig");
const v = global.Version;
const general = @import("patch_general.zig");
const multiplayer = @import("patch_multiplayer.zig");

const msg = @import("util/message.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");

// STATE

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

// DO THE THING!!!

export fn Patch() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const memory = alloc.alloc(u8, patch_size) catch unreachable;
    var off: usize = @intFromPtr(memory.ptr);

    // settings

    settings.init(alloc);

    // init

    off = hooking.init(alloc, off);
    off = global.init(alloc, off);
    off = general.init(alloc, off);
    off = multiplayer.init(alloc, off);

    // debug

    if (false) {
        msg.Message("Annodue {d}.{d}.{d} ({d})", .{
            v.major,
            v.minor,
            v.patch,
            v.build,
        }, "Patching SWE1R...", .{});
    }
}
