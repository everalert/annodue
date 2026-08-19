const std = @import("std");

const global = @import("core/Global.zig");
const AHook = @import("core/AHook.zig");
const AMemory = @import("core/AMemory.zig");
const ASettings = @import("core/ASettings.zig");

const msg = @import("util/message.zig");
const dbg = @import("util/base/base_debug.zig");
const MiB = @import("util/base/base_memory.zig").MiB;

pub const panic = dbg.annodue_panic;

export fn Init() void {
    // TODO: maybe this should be re-characterized to reflect that it's just
    // checking whether or not to cancel loading annodue
    if (!global.init()) return;

    // init

    if (!AMemory.Init()) @panic("Init(AMemory): OutOfMemory");
    const arena_perm = AMemory.PermanentAllocator();
    const arena_temp = AMemory.TemporaryAllocator();

    // TODO: reimpl alloc in init fn args
    ASettings.init(arena_perm, arena_temp) catch |e|
        std.debug.panic("Init(ASettings): {s}", .{@errorName(e)});

    AHook.init(arena_perm, arena_temp) catch |e|
        std.debug.panic("Init(AHook): {s}", .{@errorName(e)});
}

export fn Deinit() void {
    ASettings.deinit() catch {};
}
