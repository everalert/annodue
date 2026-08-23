const std = @import("std");

const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const msg = @import("util/message.zig");

const r = @import("racer");
const rt = r.Text;

const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;
const Setting = @import("core/ASettings.zig").ASettingSent;

const debug_panic = @import("util/debug/debug_panic.zig");
pub const panic = debug_panic.PanicFromContext("plugin_test", "annodue/plugin/plugin_test.pdb");

// FEATURES
// -
// - CONTROLS:      keyboard        xinput
//   ..             ..              ..
// - SETTINGS:
//   ..             type    note

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

export fn OnInit(_: *GlobalFn) callconv(.C) void {}

export fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

// HOOKS

export fn EarlyEngineUpdateA(gf: *GlobalFn) callconv(.C) void {
    if (gf.InputGetKb(.J, .JustOn)) std.debug.assert(false); // does nothing in ReleaseFast, ReleaseSmall
    if (gf.InputGetKb(.F, .JustOn)) @panic("panic test");

    //_ = gf.GDrawText(.Default, rt.hMakeText(0, 0, "GDrawText Test", .{}, null, null) catch null);
}
