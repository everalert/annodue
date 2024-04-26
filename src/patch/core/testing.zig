const std = @import("std");

const GlobalSt = @import("../global.zig").GlobalState;
const GlobalFn = @import("../global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("../global.zig").PLUGIN_VERSION;

// HOOK FUNCTIONS

pub fn EarlyEngineUpdateA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    //if (gf.InputGetKb(.J, .JustOn)) unreachable; // does nothing in ReleaseFast, ReleaseSmall
    //if (gf.InputGetKb(.F, .JustOn)) @panic("panic test");
}
