const Self = @This();

const std = @import("std");

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const mem = @import("util/memory.zig");

const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;
const Setting = @import("core/ASettings.zig").ASettingSent;

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

const GameplayTweak = struct {
    var h_s_section: ?SettingHandle = null;
    var h_s_enable: ?SettingHandle = null;
    var h_s_ds_mod_enable: ?SettingHandle = null;
    var h_s_ds_min: ?SettingHandle = null;
    var h_s_ds_drop: ?SettingHandle = null;
    var s_enable: bool = false;
    var s_ds_mod_enable: bool = false;
    var s_ds_min: f32 = 325;
    var s_ds_drop: f32 = 140;

    fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "gameplay", settingsUpdate);
        h_s_section = section;

        //h_s_enable = gf.ASettingOccupy(section, "enable", .B, .{ .b = false }, &s_enable, null);

        h_s_ds_mod_enable =
            gf.ASettingOccupy(section, "death_speed_mod_enable", .B, .{ .b = false }, &s_ds_mod_enable, null);
        h_s_ds_min =
            gf.ASettingOccupy(section, "death_speed_min", .F, .{ .f = 325 }, &s_ds_min, null);
        h_s_ds_drop =
            gf.ASettingOccupy(section, "death_speed_drop", .F, .{ .f = 140 }, &s_ds_drop, null);
    }

    fn settingsUpdate(changed: [*]Setting, len: usize) callconv(.C) void {
        var update_death_speed_mod: bool = false;

        for (changed, 0..len) |setting, _| {
            const nlen: usize = std.mem.len(setting.name);

            if (nlen == 22 and std.mem.eql(u8, "death_speed_mod_enable", setting.name[0..nlen]) or
                nlen == 15 and std.mem.eql(u8, "death_speed_min", setting.name[0..nlen]) or
                nlen == 16 and std.mem.eql(u8, "death_speed_drop", setting.name[0..nlen]))
            {
                update_death_speed_mod = true;
                continue;
            }
        }

        // TODO: add conditional thing for practice mode toggling
        if (update_death_speed_mod) {
            if (s_ds_mod_enable)
                PatchDeathSpeed(s_ds_min, s_ds_drop)
            else
                PatchDeathSpeed(325, 140);
        }
    }
};

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

export fn OnInit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    GameplayTweak.settingsInit(gf);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    PatchDeathSpeed(325, 140);
}
