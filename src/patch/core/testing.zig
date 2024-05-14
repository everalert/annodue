const std = @import("std");

const app = @import("../appinfo.zig");
const GlobalSt = app.GLOBAL_STATE;
const GlobalFn = app.GLOBAL_FUNCTION;

// HOOK FUNCTIONS

pub fn EarlyEngineUpdateA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    //if (gf.InputGetKb(.J, .JustOn)) unreachable; // does nothing in ReleaseFast, ReleaseSmall
    //if (gf.InputGetKb(.F, .JustOn)) @panic("panic test");

    //if (gf.InputGetKb(.Y, .JustOn)) _ = gf.ToastNew("Testing.zig toast", 0x00FFFFFF);
}
