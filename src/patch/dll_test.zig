const Self = @This();

const std = @import("std");

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const msg = @import("util/message.zig");

// FIXME: remove or whatever, testing
const x86 = @import("util/x86.zig");
const BOOL = std.os.windows.BOOL;
const r = @import("racer");
const Test = r.Entity.Test.Test;
const Test_HandleTerrain = r.Entity.Test.HandleTerrain;
const Trig = r.Entity.Trig.Trig;
const Trig_HandleTriggers = r.Entity.Trig.HandleTriggers;
const t = r.Text;
const mo = r.Model;
const ModelMesh_GetBehavior = mo.Mesh_GetBehavior;
const ModelMesh = mo.ModelMesh;
const ModelBehavior = mo.ModelBehavior;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// -
// - CONTROLS:      keyboard        xinput
//   ..             ..              ..
// - SETTINGS:
//   ..             type    note

fn HandleTriggersHooked(tr: *Trig, te: *Test, is_local: BOOL) callconv(.C) void {
    if (tr.pTrigDesc.Type == 202) te._fall_float_value -= 1.5;
    t.DrawText(0, 8, "Trigger {d}", .{tr.pTrigDesc.Type}, null, null) catch {};
    Trig_HandleTriggers(tr, te, is_local);
}

fn HandleTerrainHooked(te: *Test) callconv(.C) void {
    Test_HandleTerrain(te);

    const terrain_model = te._unk_0140_terrainModel;
    if (@intFromPtr(terrain_model) == 0) return;
    const behavior = ModelMesh_GetBehavior(terrain_model);
    if (@intFromPtr(behavior) == 0) return;

    const flags = behavior.TerrainFlags;

    if (flags & (1 << 5) > 0) // SLIP terrain
        te.temperature = @min(2 * r.Time.FRAMETIME.* * te.stats.CoolRate + te.temperature, 100);

    t.DrawText(0, 0, "Terrain Flags {X}", .{flags}, null, null) catch {};
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

export fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // triggers
    // 0x476E7C -> 0x476E88 (0x0C)
    // 0x476E80 = the actual call instruction
    _ = x86.call(0x476E80, @intFromPtr(&HandleTriggersHooked));

    // terrain
    // 0x47B8AF -> 0x47B8B8 (0x09)
    // 0x47B8B0 = the actual call instruction
    _ = x86.call(0x47B8B0, @intFromPtr(&HandleTerrainHooked));
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // deinit here
    _ = x86.call(0x476E80, @intFromPtr(&Trig_HandleTriggers));
    _ = x86.call(0x47B8B0, @intFromPtr(&Test_HandleTerrain));
}

// HOOKS

export fn EarlyEngineUpdateA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    //rt.DrawText(16, 16, "{s} {s}", .{
    //    PLUGIN_NAME,
    //    PLUGIN_VERSION,
    //}, null, null) catch {};
}
