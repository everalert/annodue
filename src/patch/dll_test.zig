const Self = @This();

const std = @import("std");

const GlobalState = @import("global.zig").GlobalState;
const GlobalVTable = @import("global.zig").GlobalVTable;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");

const msg = @import("util/message.zig");

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return "TestPlugin";
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return "0.0.1";
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

// HOOKS

export fn EarlyEngineUpdateAfter(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}
