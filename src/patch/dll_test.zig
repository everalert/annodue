const Self = @This();

const std = @import("std");

const GlobalState = @import("global.zig").GlobalState;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");

const msg = @import("util/message.zig");

// FIXME: need to decide if early init should even be a thing; either way need to
// eventually figure out a vtable situation tho
//export fn Init(alloc: std.mem.Allocator, memory: usize) usize {
//    _ = alloc;
//    msg.TestMessage("TEST DLL: INIT", .{});
//    return memory;
//}

export fn MenuTrackSelect_Before(gs: *GlobalState, initialized: bool) void {
    _ = gs;
    _ = initialized;
    rf.swrText_CreateEntry1(160, 120, 0, 0, 0, 190, "~F0~1~cTEST DLL TEXT MENUTRACKSELECT_BEFORE");
}

export fn TextRender_Before(gs: *GlobalState, initialized: bool) void {
    _ = initialized;
    if (gs.in_race.isOn()) {
        rf.swrText_CreateEntry1(160, 120, 0, 0, 0, 190, "~F0~1~cTEST DLL TEXT TEXTRENDER_BEFORE");
    }
}
