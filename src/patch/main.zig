const std = @import("std");
const builtin = @import("builtin");
const StackTrace = std.builtin.StackTrace;

const global = @import("core/Global.zig");
const hook = @import("core/Hook.zig");
const allocator = @import("core/Allocator.zig");
const debug = @import("core/Debug.zig");
const settings = @import("core/Settings.zig");

const msg = @import("util/message.zig");

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

pub const panic = debug.annodue_panic;

// DO THE THING!!!

export fn Init() void {
    if (!global.init()) return;

    // init

    const alloc = allocator.allocator();
    const memory = alloc.alloc(u8, patch_size) catch @panic("failed to allocate main patch memory");
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
