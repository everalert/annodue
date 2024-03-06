const Self = @This();

const std = @import("std");

const GlobalState = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFn;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");
const rc = @import("util/racer_const.zig");
const rt = @import("util/racer_text.zig");
const rto = rt.TextStyleOpts;

const PLUGIN_NAME: [*:0]const u8 = "PluginTest";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return PLUGIN_NAME;
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return PLUGIN_VERSION;
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

// HOOKS

export fn EarlyEngineUpdateA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;

    //rt.DrawText(16, 16, "{s} {s}", .{
    //    PLUGIN_NAME,
    //    PLUGIN_VERSION,
    //}, null, null) catch {};
}
