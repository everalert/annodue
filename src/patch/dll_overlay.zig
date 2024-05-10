const Self = @This();

const std = @import("std");

const GlobalSt = @import("core/Global.zig").GlobalState;
const GlobalFn = @import("core/Global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("core/Global.zig").PLUGIN_VERSION;

const debug = @import("core/Debug.zig");

const r = @import("util/racer.zig");
const rf = @import("racer").functions;
const rc = @import("racer").constants;
const rt = @import("racer").text;
const rto = rt.TextStyleOpts;

const mem = @import("util/memory.zig");
const timing = @import("util/timing.zig");

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// Usable in Practice Mode only

// FEATURES
// - Show individual lap times during race
// - Show time to overheat/underheat
// - SETTINGS:
//   enable     bool

// TODO: finish porting overlay features from original practice tool
// TODO: settings for individual elements, hot-reloadable, with local settings change handling

const PLUGIN_NAME: [*:0]const u8 = "Overlay";
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

const style_heat = rt.MakeTextHeadStyle(.Small, false, .Gray, .Right, .{rto.ToggleShadow}) catch "";
const style_heat_up = rt.MakeTextHeadStyle(.Small, false, .Red, .Right, .{rto.ToggleShadow}) catch "";
const style_heat_dn = rt.MakeTextHeadStyle(.Small, false, .Blue, .Right, .{rto.ToggleShadow}) catch "";
const style_laptime = rt.MakeTextHeadStyle(.Unk2, true, null, null, .{rto.ToggleShadow}) catch "";

const lbx: i16 = 64;
const lby: i16 = 480 - 32;
const sty: i16 = -10;

export fn EarlyEngineUpdateA(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (!gs.practice_mode or !gf.SettingGetB("overlay", "enable").?) return;

    if (gs.in_race.on()) {
        const lap: u8 = r.ReadRaceDataValue(0x78, u8);
        const race_times: [6]f32 = r.ReadRaceDataValue(0x60, [6]f32);
        const lap_times: []const f32 = race_times[0..5];

        if (gs.race_state == .Racing or (gs.race_state_new and gs.race_state == .PostRace)) {
            // draw heat timer
            const heat_s: f32 = gs.player.heat / gs.player.heat_rate;
            const cool_s: f32 = (100 - gs.player.heat) / gs.player.cool_rate;
            const heat_timer: f32 = if (gs.player.boosting.on()) heat_s else cool_s;
            const heat_style = if (gs.player.boosting.on()) style_heat_up else if (gs.player.heat < 100) style_heat_dn else style_heat;
            rt.DrawText(256, 170, "{d:0>5.3}", .{heat_timer}, null, heat_style) catch {};

            // draw lap times
            for (lap_times, 0..) |t, i| {
                if (t < 0) break;
                const x1: u8 = 48;
                const x2: u8 = 64;
                const y: u8 = 128 + @as(u8, @truncate(i)) * 16;
                const col: u32 = if (lap == i) 0xFFFFFFBE else 0xAAAAAABE;
                rt.DrawText(x1, y + 6, "{d}", .{i + 1}, col, null) catch {};
                const lt = timing.RaceTimeFromFloat(lap_times[i]);
                rt.DrawText(x2, y, "{d}:{d:0>2}.{d:0>3}", .{
                    lt.min, lt.sec, lt.ms,
                }, col, style_laptime) catch {};
            }

            // FPS
            rt.DrawText(lbx, lby + sty * 0, "{d:>2.0}  {d:>5.2}  {d:>5.3}~rFPS  ", .{
                gs.fps_avg, gs.fps * 1000, gs.dt_f,
            }, null, null) catch {};

            // DEATH counter
            if (gs.player.deaths > 0)
                rt.DrawText(lbx, lby + sty * 1, "{d}~rDETH  ", .{gs.player.deaths}, null, null) catch {};

            // FALL timer
            const oob_timer = r.ReadPlayerValue(0x2C8, f32);
            if (oob_timer > 0)
                rt.DrawText(lbx, lby + sty * 2, "{d:0>5.3}~rFall  ", .{oob_timer}, null, null) catch {};
        }
    }
}
