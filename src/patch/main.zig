const std = @import("std");
const builtin = @import("builtin");
const StackTrace = std.builtin.StackTrace;

const global = @import("core/Global.zig");
const hook = @import("core/Hook.zig");
const allocator = @import("core/AMemory.zig");
const debug = @import("core/Debug.zig");
const asettings = @import("core/ASettings.zig");

const msg = @import("util/message.zig");
const MiB = @import("util/base/base_memory.zig").MiB;

const patch_size = MiB(u32, 4);

pub const panic = debug.annodue_panic;

// DO THE THING!!!

export fn Init() void {
    if (!global.init()) return;
    if (!allocator.Init()) @panic("failed to initialize memory");

    // init

    const memory = allocator.PermanentAlloc(patch_size);
    global.GLOBAL_STATE.patch_memory = @ptrCast(memory.ptr);
    global.GLOBAL_STATE.patch_size = memory.len;
    global.GLOBAL_STATE.patch_offset = @intFromPtr(memory.ptr);

    // TODO: reimpl alloc in init fn args
    asettings.init() catch {};
    hook.init();

    // debug

    if (false) {
        msg.Message("{s}", .{global.VersionStr}, "Patching SWE1R...", .{});
    }
}

export fn Deinit() void {
    asettings.deinit() catch {};
}
