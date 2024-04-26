const Self = @This();

const std = @import("std");

const GlobalSt = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const debug = @import("core/Debug.zig");

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");
const rc = @import("util/racer_const.zig");

const mem = @import("util/memory.zig");

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// - Patch DeathSpeedMin (minimum speed required to die from collision)
// - Patch DeathSpeedDrop (minimum speed loss in 1 frame to die from collision)
// - SETTINGS:
//   * all settings require game restart to apply
//   death_speed_mod_enable     bool
//   death_speed_min            f32
//   death_speed_drop           f32

// TODO: hot reloading settings
// TODO: integrate with modal ecosystem, once that is ready

const PLUGIN_NAME: [*:0]const u8 = "GameplayTweak";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// DEATHSPEED

fn PatchDeathSpeed(min: f32, drop: f32) void {
    _ = mem.write(0x4C7BB8, f32, min);
    _ = mem.write(0x4C7BBC, f32, drop);
}

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

export fn OnInit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gs;
    // TODO: add conditional thing for practice mode toggling
    if (gf.SettingGetB("gameplay", "death_speed_mod_enable").?) {
        const dsm: f32 = gf.SettingGetF("gameplay", "death_speed_min") orelse 325;
        const dsd: f32 = gf.SettingGetF("gameplay", "death_speed_drop") orelse 140;
        PatchDeathSpeed(dsm, dsd);
    }
}

export fn OnInitLate(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
    PatchDeathSpeed(325, 140);
}
