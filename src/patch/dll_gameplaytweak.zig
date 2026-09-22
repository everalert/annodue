const Self = @This();

const std = @import("std");

const PluginAPI = @import("util/root.zig").PluginAPI;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;

const mem = @import("util/memory.zig");

const plug = @import("util/plugin/plugin.zig");
const ASettingMessage = plug.ASettingMessage;
const ASettingHandle = plug.ASettingHandle;
const ASETTING_HANDLE_NULL = plug.ASETTING_HANDLE_NULL;
const plugh = plug.helper;
const RAddressHandleInfo = plugh.RAddressHandleInfo;

const debug_panic = @import("util/debug/debug_panic.zig");
pub const panic = debug_panic.PanicFromContext("plugin_gameplaytweak", "annodue/plugin/plugin_gameplaytweak.pdb");

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
    var h_s_section: ?ASettingHandle = null;
    var h_s_enable: ?ASettingHandle = null;
    var h_s_ds_mod_enable: ?ASettingHandle = null;
    var h_s_ds_min: ?ASettingHandle = null;
    var h_s_ds_drop: ?ASettingHandle = null;
    var s_enable: bool = false;
    var s_ds_mod_enable: bool = false;
    var s_ds_min: f32 = 325;
    var s_ds_drop: f32 = 140;

    var h_ar_deathspeed = RAddressHandleInfo.InitLen(0x4C7BB8, 8); // deathspeedmin, deathspeeddrop

    var api: *PluginAPI = undefined;

    fn settingsInit(gf: *PluginAPI) void {
        const section = gf.ASettingSectionOccupy(ASETTING_HANDLE_NULL, "gameplay", settingsUpdate);
        h_s_section = section;

        //h_s_enable = gf.ASettingOccupy(section, "enable", .B, .{ .B = false }, &s_enable, null);

        h_s_ds_mod_enable =
            gf.ASettingOccupy(section, "death_speed_mod_enable", .B, .{ .B = false }, &s_ds_mod_enable, null);
        h_s_ds_min =
            gf.ASettingOccupy(section, "death_speed_min", .F, .{ .F = 325 }, &s_ds_min, null);
        h_s_ds_drop =
            gf.ASettingOccupy(section, "death_speed_drop", .F, .{ .F = 140 }, &s_ds_drop, null);
    }

    fn settingsUpdate(changed: [*]ASettingMessage, len: usize) callconv(.C) void {
        var update_death_speed_mod: bool = false;

        for (changed, 0..len) |setting, _| {
            const nlen: usize = std.mem.len(setting.Name);

            if (nlen == 22 and std.mem.eql(u8, "death_speed_mod_enable", setting.Name[0..nlen]) or
                nlen == 15 and std.mem.eql(u8, "death_speed_min", setting.Name[0..nlen]) or
                nlen == 16 and std.mem.eql(u8, "death_speed_drop", setting.Name[0..nlen]))
            {
                update_death_speed_mod = true;
                continue;
            }
        }

        // TODO: add conditional thing for practice mode toggling
        if (update_death_speed_mod) {
            if (s_ds_mod_enable)
                PatchDeathSpeed(api, s_ds_min, s_ds_drop)
            else
                PatchDeathSpeed(api, 325, 140);
        }
    }
};

// DEATHSPEED

fn PatchDeathSpeed(api: *PluginAPI, min: f32, drop: f32) void {
    const handle = GameplayTweak.h_ar_deathspeed.Handle;
    if (!plugh.RAddressPatchToggle(api, handle, true)) return;

    if (!api.RAddressRangeWriteSt(handle)) return;
    defer api.RAddressRangeWriteEd(handle);

    _ = mem.Write(0x4C7BB8, f32, min);
    _ = mem.Write(0x4C7BBC, f32, drop);
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

export fn OnInit(gf: *PluginAPI) callconv(.C) void {
    // FIXME: stop doing this
    GameplayTweak.api = gf;

    GameplayTweak.h_ar_deathspeed.Reserve(gf);

    GameplayTweak.settingsInit(gf);
}

export fn OnInitLate(_: *PluginAPI) callconv(.C) void {}

export fn OnDeinit(_: *PluginAPI) callconv(.C) void {}
