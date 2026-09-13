const std = @import("std");

const global = @import("core/Global.zig");
const AHook = @import("core/AHook.zig");
const AMemory = @import("core/AMemory.zig");
const ASettings = @import("core/ASettings.zig");
const RAddress = @import("core/RAddress.zig");

const MiB = @import("util/base/base_memory.zig").MiB;

const debug_panic = @import("util/debug/debug_panic.zig");
pub const panic = debug_panic.PanicFromContext("annodue", "annodue/annodue.pdb");

export fn Init() void {
    // TODO: maybe this should be re-characterized to reflect that it's just
    // checking whether or not to cancel loading annodue
    if (!global.init()) return;

    // init

    // ring 0

    if (!AMemory.Init()) @panic("Init(AMemory): OutOfMemory");
    const arena_perm = AMemory.PermanentAllocator();
    const arena_temp = AMemory.TemporaryAllocator();

    // ring 1

    ASettings.init(arena_perm, arena_temp) catch |e|
        std.debug.panic("Init(ASettings): {s}", .{@errorName(e)});
    RAddress.Init(arena_perm);

    // ring 2

    // TODO: API should be initialized separately (very early ring, possibly ring 0
    //  if it can be done with no subsystem dependencies) to the hooking and loading
    //  plugins/core; most init should happen during normal API OnInit as subsystems
    //  are individually "loaded" into the API, manually importing modules to gain
    //  access to API functions should be basically nonexistent after API is initialized
    AHook.init(arena_perm, arena_temp) catch |e|
        std.debug.panic("Init(AHook): {s}", .{@errorName(e)});
}

export fn Deinit() void {
    ASettings.deinit() catch {};
}
