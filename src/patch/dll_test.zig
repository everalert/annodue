const Self = @This();

const std = @import("std");

const GlobalState = @import("global.zig").GlobalState;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");

const msg = @import("util/message.zig");

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return "TestPlugin";
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return "0.0.0";
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;
}

export fn OnInitLate(gs: *GlobalState, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalState, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;
}

//export fn OnEnable(gs: *GlobalState, initialized: bool) callconv(.C) void {}
//export fn OnDisable(gs: *GlobalState, initialized: bool) callconv(.C) void {}

// HOOKS

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
