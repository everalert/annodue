const std = @import("std");

const GlobalSt = @import("Global.zig").GlobalState;
const GlobalFn = @import("Global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("Global.zig").PLUGIN_VERSION;

// HOOK FUNCTIONS

pub fn EarlyEngineUpdateA(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (gf.InputGetKb(.J, .JustOn)) unreachable; // does nothing in ReleaseFast, ReleaseSmall
    if (gf.InputGetKb(.F, .JustOn)) @panic("panic test");

    if (gf.InputGetKb(.Y, .JustOn)) _ = gf.ToastNew("Testing.zig toast", 0x00FFFFFF);
}
