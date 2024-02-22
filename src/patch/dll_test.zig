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

export fn MenuTrackSelectBefore(gs: *GlobalState, initialized: bool) callconv(.C) void {
    var buf: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "~F0~1~sTest DLL MenuTrackSelect: state {x}, init {any}", .{
        @intFromPtr(gs),
        initialized,
    }) catch unreachable;
    rf.swrText_CreateEntry1(16, 16, 0, 0, 0, 190, &buf);
}

export fn TextRenderBefore(gs: *GlobalState, initialized: bool) callconv(.C) void {
    var buf: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "~F0~1~sTest DLL TextRender: state {x}, init {any}", .{
        @intFromPtr(gs),
        initialized,
    }) catch unreachable;
    rf.swrText_CreateEntry1(16, 24, 0, 0, 0, 190, &buf);

    if (gs.in_race.isOn()) {
        rf.swrText_CreateEntry1(160, 120, 0, 0, 0, 190, "~F0~1~cTEST DLL TEXT TEXTRENDER_BEFORE");
    }
}
