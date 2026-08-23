const Self = @This();

const std = @import("std");

const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const rrd = @import("racer").RaceData;
const rete = @import("racer").Entity.Test;
const rt = @import("racer").Text;
const rto = rt.TextStyleOpts;
const ModelMesh_GetBehavior = @import("racer").Model.Mesh_GetBehavior;
const rti = @import("racer").Time;

const mem = @import("util/memory.zig");
const timing = @import("util/timing.zig");
const ToggleState = @import("util/toggle_state.zig").ToggleState;

const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;

const debug_panic = @import("util/debug/debug_panic.zig");
pub const panic = debug_panic.PanicFromContext("plugin_overlay", "annodue/plugin/plugin_overlay.pdb");

// Usable in Practice Mode only

// FEATURES
// - Show individual lap times during race
// - Show time to overheat/underheat
// - SETTINGS:
//   enable             bool
//   show_fps           bool
//   show_fps_simple    bool
//   show_speed         bool
//   show_speed_raw     bool
//   show_speed_offsets bool
//   show_heat_timer    bool
//   show_lap_times     bool
//   show_death_count   bool
//   show_fall_timer    bool

// TODO: finish porting overlay features from original practice tool
// TODO: implement additional 'show overlay' core setting used on layer directly, see GDraw.zig
// TODO: reconsider location of overlay features after global overlay is formalized as above

const PLUGIN_NAME: [*:0]const u8 = "Overlay";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const Overlay = struct {
    var h_s_section: ?SettingHandle = null;
    var h_s_enable: ?SettingHandle = null;
    var h_s_show_lap_times: ?SettingHandle = null;
    var h_s_show_heat_timer: ?SettingHandle = null;
    var h_s_show_death_count: ?SettingHandle = null;
    var h_s_show_fall_timer: ?SettingHandle = null;
    var h_s_show_mfg_timer: ?SettingHandle = null;
    var h_s_show_fps: ?SettingHandle = null;
    var h_s_show_fps_simple: ?SettingHandle = null;
    var h_s_show_speed: ?SettingHandle = null;
    var h_s_show_speed_raw: ?SettingHandle = null;
    var h_s_show_speed_offsets: ?SettingHandle = null;
    var s_enable: bool = false;
    var s_show_lap_times: bool = true;
    var s_show_heat_timer: bool = true;
    var s_show_death_count: bool = true;
    var s_show_fall_timer: bool = true;
    var s_show_mfg_timer: bool = true;
    var s_show_fps: bool = true;
    var s_show_fps_simple: bool = false;
    var s_show_speed: bool = true;
    var s_show_speed_raw: bool = true;
    var s_show_speed_offsets: bool = true;

    var fast_state: ToggleState = .Off;
    var fast_time: f32 = 0;
    var slow_state: ToggleState = .Off;
    var slow_time: f32 = 0;
    var swst_state: ToggleState = .Off;
    var swst_time: f32 = 0;
    var mfg_time: f32 = 0;
    var mfg_timing: bool = false;
    var mfg_delay: f32 = 0;
    var mfg_power: f32 = 0;
    var speed: f32 = 0;
    var speed_prev: f32 = 0;

    fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "overlay", null);
        h_s_section = section;

        h_s_enable =
            gf.ASettingOccupy(section, "enable", .B, .{ .b = false }, &s_enable, null);
        h_s_show_lap_times =
            gf.ASettingOccupy(section, "show_lap_times", .B, .{ .b = true }, &s_show_lap_times, null);
        h_s_show_heat_timer =
            gf.ASettingOccupy(section, "show_heat_timer", .B, .{ .b = true }, &s_show_heat_timer, null);
        h_s_show_death_count =
            gf.ASettingOccupy(section, "show_death_count", .B, .{ .b = true }, &s_show_death_count, null);
        h_s_show_fall_timer =
            gf.ASettingOccupy(section, "show_fall_timer", .B, .{ .b = true }, &s_show_fall_timer, null);
        h_s_show_mfg_timer =
            gf.ASettingOccupy(section, "show_mfg_timer", .B, .{ .b = true }, &s_show_mfg_timer, null);
        h_s_show_fps =
            gf.ASettingOccupy(section, "show_fps", .B, .{ .b = true }, &s_show_fps, null);
        h_s_show_fps_simple =
            gf.ASettingOccupy(section, "show_fps_simple", .B, .{ .b = false }, &s_show_fps_simple, null);
        h_s_show_speed =
            gf.ASettingOccupy(section, "show_speed", .B, .{ .b = true }, &s_show_speed, null);
        h_s_show_speed_raw =
            gf.ASettingOccupy(section, "show_speed_raw", .B, .{ .b = true }, &s_show_speed_raw, null);
        h_s_show_speed_offsets =
            gf.ASettingOccupy(section, "show_speed_offsets", .B, .{ .b = true }, &s_show_speed_offsets, null);
    }
};

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

export fn OnInit(gf: *GlobalFn) callconv(.C) void {
    Overlay.settingsInit(gf);
}

export fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

// HOOKS

const style_heat = rt.hMakeTextHeadStyle(.Small, false, .Gray, .Right, .{rto.ToggleShadow}) catch "";
const style_heat_up = rt.hMakeTextHeadStyle(.Small, false, .Red, .Right, .{rto.ToggleShadow}) catch "";
const style_heat_dn = rt.hMakeTextHeadStyle(.Small, false, .Blue, .Right, .{rto.ToggleShadow}) catch "";
const style_laptime = rt.hMakeTextHeadStyle(.Unk2, true, null, null, .{rto.ToggleShadow}) catch "";

const lbx: i16 = 48;
const lby: i16 = 128 + 16 * 6;
const sty: i16 = 12;

export fn Draw2DB(gf: *GlobalFn) callconv(.C) void {
    if (!Overlay.s_enable) return;

    if (gf.SInRace().on() and !gf.GHideRaceUIIsOn()) {
        const p = rete.pPlayer.*.?;

        if (gf.SInRace() == .JustOn or p.flags1.IS_DEAD) {
            Overlay.fast_state = .Off;
            Overlay.slow_state = .Off;
            Overlay.swst_state = .Off;
            Overlay.speed = 0;
            Overlay.speed_prev = 0;
            Overlay.mfg_timing = false;
            Overlay.mfg_time = 0;
        }

        // preprocessing

        const lap: u32 = rrd.pPlayer.*.?.lap;
        const lap_times: []const f32 = &rrd.pPlayer.*.?.time.lap;

        const terrain_model = p._unk_0140_terrainModel;
        const behavior = if (terrain_model) |tm| ModelMesh_GetBehavior(tm) else null;
        const grounded = p.flags2.IS_NEAR_GROUND;
        Overlay.fast_state.update(behavior != null and behavior.?.TerrainFlags.FAST);
        Overlay.slow_state.update(grounded and behavior != null and behavior.?.TerrainFlags.SLOW);
        Overlay.swst_state.update(grounded and behavior != null and behavior.?.TerrainFlags.SWST);
        Overlay.fast_time = if (Overlay.fast_state.on()) Overlay.fast_time + rti.FRAMETIME.* else 0;
        Overlay.slow_time = if (Overlay.slow_state.on()) Overlay.slow_time + rti.FRAMETIME.* else 0;
        Overlay.swst_time = if (Overlay.swst_state.on()) Overlay.swst_time + rti.FRAMETIME.* else 0;

        if (p._fall_float_rate > 0.001 and p.nextPosition.x == p.positionPrev.x and p.nextPosition.y == p.positionPrev.y and p.nextPosition.z == p.positionPrev.z) {
            Overlay.mfg_time = if (!Overlay.mfg_timing) 0 else Overlay.mfg_time + rti.FRAMETIME.*;
            Overlay.mfg_timing = true;
            Overlay.mfg_power = p._fall_float_rate;
        } else {
            if (Overlay.mfg_timing) {
                Overlay.mfg_delay = 1.0;
                Overlay.mfg_timing = false;
            } else {
                Overlay.mfg_delay -= rti.FRAMETIME.*;
            }
            if (Overlay.mfg_delay <= 0) {
                Overlay.mfg_time = 0;
            }
        }

        Overlay.speed_prev = Overlay.speed;
        Overlay.speed = if (Overlay.s_show_speed_raw) rete.GetSpeedBase(p) + rete.GetSpeedBoost(p) else @max(p.speed, 0.0);

        // rendering

        if (gf.SRaceState() == .Racing or (gf.SRaceStateNew() and gf.SRaceState() == .PostRace)) {
            if (Overlay.s_show_heat_timer) {
                // FIXME: remove
                //const heat_s: f32 = gf.SPlayerHeat() / gf.SPlayerHeatRate();
                //const cool_s: f32 = (100 - gf.SPlayerHeat()) / gf.SPlayerCoolRate();
                const heat_s = rete.GetPlayerTimeToOverheat();
                const cool_s = rete.GetPlayerTimeToUnderheat();
                const heat_timer: f32 = if (gf.SPlayerBoosting().on()) heat_s else cool_s;
                const heat_style = if (gf.SPlayerBoosting().on()) style_heat_up else if (p.temperature < 100) style_heat_dn else style_heat;
                _ = gf.GDrawText(
                    .OverlayP,
                    rt.hMakeText(256, 170, "{d:0>5.3}", .{heat_timer}, null, heat_style) catch null,
                );
            }

            if (Overlay.s_show_lap_times) {
                for (lap_times, 0..) |t, i| {
                    if (t < 0) break;
                    const x1: u8 = 48;
                    const x2: u8 = 64;
                    const y: u8 = 128 + @as(u8, @truncate(i)) * 16;
                    const col: u32 = if (lap == i) 0xFFFFFFBE else 0xAAAAAABE;
                    _ = gf.GDrawText(.Overlay, rt.hMakeText(x1, y + 6, "{d}", .{i + 1}, col, null) catch null);
                    const lt = timing.RaceTimeFromFloat(lap_times[i]);
                    _ = gf.GDrawText(.Overlay, rt.hMakeText(x2, y, "{d}:{d:0>2}.{d:0>3}", .{
                        lt.min, lt.sec, lt.ms,
                    }, col, style_laptime) catch null);
                }
            }

            if (Overlay.s_show_fps) {
                if (Overlay.s_show_fps_simple) {
                    _ = gf.GDrawText(.Overlay, rt.hMakeText(624, 464, "~r{d:>2.0}", .{
                        gf.SFPSAvg(),
                    }, null, null) catch null);
                } else {
                    _ = gf.GDrawText(.Overlay, rt.hMakeText(624, 464, "~r{d:>2.0}  {d:>5.2}  {d:>5.3}", .{
                        gf.SFPSAvg(), rti.FPS.*, rti.FRAMETIME.*,
                    }, null, null) catch null);
                }
            }

            if (Overlay.s_show_death_count) {
                if (gf.SPlayerDeaths() > 0)
                    _ = gf.GDrawText(.Overlay, rt.hMakeText(lbx, lby + sty * 0, "~5{d} ~1{s}", .{
                        gf.SPlayerDeaths(), if (gf.SPlayerDeaths() > 1) "Deaths" else "Death",
                    }, null, null) catch null);
            }

            if (Overlay.s_show_fall_timer) {
                const oob_timer = rete.pPlayer.*.?.fallTimer;
                if (oob_timer > 0)
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(lbx, lby + sty * 1, "~3{d:0>5.3} ~1Fall", .{
                        oob_timer,
                    }, null, null) catch null);
            }

            if (Overlay.s_show_mfg_timer) {
                if (Overlay.mfg_time > 0 or Overlay.mfg_delay > 0) {
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(lbx, lby + sty * 2, "~3MFG ~1{d:0>5.3}", .{
                        Overlay.mfg_time,
                    }, null, null) catch null);
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(lbx, lby + sty * 3 - 4, "~1{d:0>5.3}", .{
                        Overlay.mfg_power,
                    }, null, null) catch null);
                }
            }

            if (Overlay.s_show_speed) {
                const b = gf.SPlayerBoosting().on();

                const speed_cur = Overlay.speed;
                const speed_dif = speed_cur - Overlay.speed_prev;
                const speed_max = if (b) p.stats.MaxSpeed + p.stats.BoostThrust else p.stats.MaxSpeed;
                const speed_percent = speed_cur / speed_max;

                const speed_color: u32 = if (b) 0xFF6759FE else 0x26C5FFFE;
                const x: i32 = 508;
                const y: i32 = 426;

                _ = gf.GDrawText(.OverlayP, rt.hMakeText(x, y, "~r{d:>5.3}", .{
                    speed_cur,
                }, speed_color, null) catch null);
                _ = gf.GDrawText(.OverlayP, rt.hMakeText(x, y + 8, "~r~1{d:>5.3}", .{
                    speed_dif,
                }, null, null) catch null);
                _ = gf.GDrawText(.OverlayP, rt.hMakeText(x, y + 19, "~r~3{d:>5.3}", .{
                    speed_percent * 100,
                }, null, null) catch null);
            }

            if (Overlay.s_show_speed_offsets) {
                var x: i16 = 420;
                const y: i16 = 426;
                const mx: i16 = 64;

                if (p.speedOffset != 0.0 or p.speedMult != 1.0) {
                    const col_off: u32 = if (p.speedOffset != 0.0) 0xFFFFFFBE else 0xAAAAAABE;
                    const col_mul: u32 = if (p.speedMult != 1.0) 0xFFFFFFBE else 0xAAAAAABE;
                    const x2 = x + 8;
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(x2, y, "~r{d:>5.3}", .{
                        p.speedOffset,
                    }, col_off, null) catch null);
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(x2, y + 8, "~rx{d:>5.3}", .{
                        p.speedMult,
                    }, col_mul, null) catch null);
                    x -= mx * 1;
                }

                if (Overlay.fast_time > 0) {
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(x, y, "~r~3FAST", .{}, null, null) catch null);
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(x, y + 8, "~r~1{d:>5.3}", .{
                        Overlay.fast_time,
                    }, null, null) catch null);
                    x -= mx * 1;
                }

                if (Overlay.slow_time > 0) {
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(x, y, "~r~3SLOW", .{}, null, null) catch null);
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(x, y + 8, "~r~1{d:>5.3}", .{
                        Overlay.slow_time,
                    }, null, null) catch null);
                    x -= mx * 1;
                }

                if (Overlay.swst_time > 0) {
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(x, y, "~r~3SWST", .{}, null, null) catch null);
                    _ = gf.GDrawText(.OverlayP, rt.hMakeText(x, y + 8, "~r~1{d:>5.3}", .{
                        Overlay.swst_time,
                    }, null, null) catch null);
                    x -= mx * 1;
                }
            }
        }
    }
}
