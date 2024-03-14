const Self = @This();

const std = @import("std");

const GlobalSt = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");
const rc = @import("util/racer_const.zig");

const mem = @import("util/memory.zig");

// DEATHSPEED

fn PatchDeathSpeed(min: f32, drop: f32) void {
    _ = mem.write(0x4C7BB8, f32, min);
    _ = mem.write(0x4C7BBC, f32, drop);
}

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return "GameplayTweak";
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return "0.0.1";
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gs;
    if (gf.SettingGetB("general", "death_speed_mod_enable").?) {
        const dsm: f32 = gf.SettingGetF("general", "death_speed_min") orelse 325;
        const dsd: f32 = gf.SettingGetF("general", "death_speed_drop") orelse 140;
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
