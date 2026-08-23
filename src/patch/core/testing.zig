const std = @import("std");

const app = @import("../appinfo.zig");
const GlobalFn = app.GLOBAL_FUNCTION;

const pdbparse = @import("../util/debug/debug_pdbparse.zig");

// HOOK FUNCTIONS

pub fn OnInit(_: *GlobalFn) callconv(.C) void {}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

pub fn EarlyEngineUpdateA(gf: *GlobalFn) callconv(.C) void {
    if (gf.InputGetKb(.J, .JustOn)) std.debug.assert(false); // does nothing in ReleaseFast, ReleaseSmall
    if (gf.InputGetKb(.F, .JustOn)) @panic("panic test");

    //if (gf.InputGetKb(.Y, .JustOn)) _ = gf.ToastNew("Testing.zig toast", 0x00FFFFFF);
}
