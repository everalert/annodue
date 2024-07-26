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

// FIXME: remove, for testing
const h = @import("core/ASettings.zig").Handle;
const nh = @import("core/ASettings.zig").NullHandle;
const s = struct {
    var hsec: ?h = null;
    var hset1: ?h = null;
    var hset2: ?h = null;
    var hset3: ?h = null;
    var hset4: ?h = null;
};

export fn OnInit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    s.hsec = gf.ASettingSectionOccupy(nh, "test", null);
    s.hset1 = gf.ASettingOccupy(s.hsec.?, "valueb", .B, .{ .b = true }, null);
    s.hset2 = gf.ASettingOccupy(s.hsec.?, "valuef", .F, .{ .f = 135.79 }, null);
    s.hset3 = gf.ASettingOccupy(s.hsec.?, "valueu", .U, .{ .u = 97531 }, null);
    s.hset4 = gf.ASettingOccupy(s.hsec.?, "valuestr", .Str, .{ .str = "stringlmao" }, null);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

// HOOKS

export fn EarlyEngineUpdateA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    //_ = gf.GDrawText(.Default, rt.MakeText(0, 0, "GDrawText Test", .{}, null, null) catch null);
}
