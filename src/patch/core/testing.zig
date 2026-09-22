const std = @import("std");

const PluginAPI = @import("../util/root.zig").PluginAPI;

const pdbparse = @import("../util/debug/debug_pdbparse.zig");

// HOOK FUNCTIONS

pub fn OnInit(_: *PluginAPI) callconv(.C) void {}

pub fn OnInitLate(_: *PluginAPI) callconv(.C) void {}

pub fn OnDeinit(_: *PluginAPI) callconv(.C) void {}

pub fn EarlyEngineUpdateA(_: *PluginAPI) callconv(.C) void {
    //if (gf.InputGetKb(.J, .JustOn)) unreachable; // does nothing in ReleaseFast, ReleaseSmall
    //if (gf.InputGetKb(.F, .JustOn)) @panic("panic test");

    //if (gf.InputGetKb(.Y, .JustOn)) _ = gf.ToastNew("Testing.zig toast", 0x00FFFFFF);
}
