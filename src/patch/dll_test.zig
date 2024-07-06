const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const msg = @import("util/message.zig");

const r = @import("racer");
const rt = r.Text;

// FIXME: remove or whatever, testing
const Handle = @import("util/handle_map.zig").Handle;
const HandleStatic = @import("util/handle_map_static.zig").Handle;
const BOOL = std.os.windows.BOOL;
const Test = r.Entity.Test.Test;
const Trig = r.Entity.Trig.Trig;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// -
// - CONTROLS:      keyboard        xinput
//   ..             ..              ..
// - SETTINGS:
//   ..             type    note

var TriggerHandle1: ?Handle(u16) = null;
var TriggerHandle2: ?Handle(u16) = null;

fn TriggerBounce(_: *Trig, te: *Test, _: BOOL, settings: u16) callconv(.C) void {
    const strength: f32 = if (settings > 0) @as(f32, @floatFromInt(settings)) / 100 else 1.5;
    te._fall_float_value -= strength;
}

var TerrainHandle: ?HandleStatic(u16) = null;

fn TerrainCooldown(te: *Test) callconv(.C) void {
    te.temperature = @min(2 * r.Time.FRAMETIME.* * te.stats.CoolRate + te.temperature, 100);
}

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

export fn OnInit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    TriggerHandle1 = gf.RTriggerRequest(2000, TriggerBounce, null, null, null); // should fail
    TriggerHandle2 = gf.RTriggerRequest(5000, TriggerBounce, null, null, null);
    TerrainHandle = gf.RTerrainRequest(0, 18, TerrainCooldown);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (TriggerHandle1) |h| gf.RTriggerRelease(h);
    if (TriggerHandle2) |h| gf.RTriggerRelease(h);
    if (TerrainHandle) |h| gf.RTerrainRelease(h);
}

// HOOKS

export fn EarlyEngineUpdateA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    //rt.DrawText(16, 16, "{s} {s}", .{
    //    PLUGIN_NAME,
    //    PLUGIN_VERSION,
    //}, null, null) catch {};
}
