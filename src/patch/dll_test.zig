const std = @import("std");

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const msg = @import("util/message.zig");

const r = @import("racer");
const rt = r.Text;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

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

export fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

// HOOKS

const s = struct {
    var pSprite: ?*r.Quad.Sprite = null;
};

export fn EarlyEngineUpdateA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    //_ = gf.GDrawText(.Default, rt.MakeText(0, 0, "GDrawText Test", .{}, null, null) catch null);
}
