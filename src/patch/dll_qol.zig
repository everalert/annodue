const Self = @This();

const std = @import("std");
const win = std.os.windows;
const w32 = @import("zigwin32");
const w32wm = w32.ui.windows_and_messaging;
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;
const XINPUT_GAMEPAD_BUTTON_INDEX = @import("core/Input.zig").XINPUT_GAMEPAD_BUTTON_INDEX;

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;

const debug = @import("core/Debug.zig");

const timing = @import("util/timing.zig");
const spatial = @import("util/spatial.zig");
const Menu = @import("util/menu.zig").Menu;
const InputGetFnType = @import("util/menu.zig").InputGetFnType;
const mi = @import("util/menu_item.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");
const st = @import("util/active_state.zig");

const rg = @import("racer").Global;
const rti = @import("racer").Time;
const rt = @import("racer").Text;
const ri = @import("racer").Input;
const rv = @import("racer").Vehicle;
const rtr = @import("racer").Track;
const rso = @import("racer").Sound;
const rvi = @import("racer").Video;
const rrd = @import("racer").RaceData;
const re = @import("racer").Entity;
const rto = rt.TextStyleOpts;

const InputMap = @import("core/Input.zig").InputMap;
const ButtonInputMap = @import("core/Input.zig").ButtonInputMap;
const AxisInputMap = @import("core/Input.zig").AxisInputMap;
const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// - fix: remove double mouse cursor
// - fix: pause game with xinput controller (maps Start -> Esc)
// - fix: toggle Jinn Reeso with cheat, instead of only enabling
// - fix: toggle Cy Yunga with cheat, instead of only enabling
// - fix: bugfix Cy Yunga cheat having no audio
// - fix: bugfix map rendering not accounting for hi-res flag
// - fix: remove 1px gap on right and bottom of viewport when rendering sprites
//     - this may cut off sprites placed right at the edge, depending on your resolution settings
// - feat: quick restart
//     - CONTROLS:          Tab+Esc          Back+Start
// - feat: quick race menu
//     - create a new race from inside a race
//     - select pod, track, upgrade stack and other race settings
//     - CONTROLS:          keyboard        xinput
//       Open                       Esc             Start           Hold or double-tap while unpaused
//       Close                      Esc             B
//       Navigate                   ↑↓→←            D-Pad
//       Interact                   Enter           A
//       Quick Confirm              Space           Start
//       All Upgrades MIN           Home            LB              While highlighting any upgrade
//       All Upgrades MAX           End             RB              While highlighting any upgrade
//       Scroll prev FPS preset     Home            LB
//       Scroll next FPS preset     End             RB
//       Scroll prev planet         Home            LB              While highlighting TRACK
//       Scroll next planet         End             RB              While highlighting TRACK
// - feat: end-race stats readout
//     - tfps
//     - full upgrade stack with healths
//     - death count
//     - total boost duration
//     - boost ratio
//     - first boost timestamp
//     - underheat duration
//     - fire finish duration
//     - overheat duration
// - feat: show milliseconds on all timers
// - feat: limit fps during races (configurable via quick race menu)
// - feat: skip planet cutscene
// - feat: skip podium cutscene
// - feat: custom default number of racers
// - feat: custom default number of laps
// - feat: fast countdown timer
// - SETTINGS:
//   quick_restart_enable       bool
//   quick_race_menu_enable     bool
//   ms_timer_enable            bool
//   fps_limiter_enable         bool
//   default_racers             u32     max 12
//   default_laps               u32     max 5
//   fast_countdown_enable      bool
//   fast_countdown_duration    f32     min 0.05, max 3.00

// TODO: dinput controls
// TODO: setting for fps limiter default value
// TODO: global fps limiter (i.e. not only in race)
// TODO: figure out wtf to do to manage state through hot-reload etc.
// FIXME: quick race menu stops working after hot reload??
// TODO: split this because it's getting unruly
//   maybe -- quality of life + game bugfixes + non-gameplay extra features
// TODO: settings for patching jinn/cy cheats

const PLUGIN_NAME: [*:0]const u8 = "QualityOfLife";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const QolState = struct {
    var h_s_section: ?SettingHandle = null;
    var h_s_quickstart: ?SettingHandle = null;
    var h_s_quickrace: ?SettingHandle = null;
    var h_s_default_racers: ?SettingHandle = null;
    var h_s_default_laps: ?SettingHandle = null;
    var h_s_ms_timer: ?SettingHandle = null;
    var h_s_fps_limiter: ?SettingHandle = null;
    var h_s_skip_planet_cutscenes: ?SettingHandle = null;
    var h_s_skip_podium_cutscene: ?SettingHandle = null;
    var h_s_fix_viewport_edges: ?SettingHandle = null;
    var quickstart: bool = false;
    var quickrace: bool = false;
    var default_racers: u32 = 12;
    var default_laps: u32 = 3;
    var ms_timer: bool = false;
    var fps_limiter: bool = false;
    var skip_planet_cutscenes: bool = false;
    var skip_podium_cutscene: bool = false;
    var fix_viewport_edges: bool = false;

    var input_pause_data = ButtonInputMap{ .kb = .ESCAPE, .xi = .START };
    var input_unpause_data = ButtonInputMap{ .kb = .ESCAPE, .xi = .B };
    var input_quickstart_data = ButtonInputMap{ .kb = .TAB, .xi = .BACK };
    var input_pause = input_pause_data.inputMap();
    var input_unpause = input_unpause_data.inputMap();
    var input_quickstart = input_quickstart_data.inputMap();

    fn UpdateInput(gf: *GlobalFn) callconv(.C) void {
        input_pause.update(gf);
        input_unpause.update(gf);
        input_quickstart.update(gf);
    }

    fn HandleSettings(gf: *GlobalFn) callconv(.C) void {
        quickstart = gf.SettingGetB("qol", "quick_restart_enable") orelse false;
        quickrace = gf.SettingGetB("qol", "quick_race_menu_enable") orelse false;
        default_racers = gf.SettingGetU("qol", "default_racers") orelse 12;
        default_laps = gf.SettingGetU("qol", "default_laps") orelse 3;
        ms_timer = gf.SettingGetB("qol", "ms_timer_enable") orelse false;
        fps_limiter = gf.SettingGetB("qol", "fps_limiter_enable") orelse false;
        skip_planet_cutscenes = gf.SettingGetB("qol", "skip_planet_cutscenes") orelse false;
        skip_podium_cutscene = gf.SettingGetB("qol", "skip_podium_cutscene") orelse false;
        fix_viewport_edges = gf.SettingGetB("qol", "fix_viewport_edges") orelse false;

        if (!quickrace) QuickRaceMenu.close();
        // FIXME: add these to deinit?
        PatchHudTimerMs(ms_timer);
        PatchPlanetCutscenes(skip_planet_cutscenes);
        PatchPodiumCutscene(skip_podium_cutscene);
        PatchViewportEdges(fix_viewport_edges);
    }
};

// HUD TIMER MS

// TODO: cleanup
fn PatchHudTimerMs(enable: bool) void {
    const draw_fn = if (enable) rt.swrText_DrawTime3 else rt.swrText_DrawTime2;
    const end_race_timer_offset: u8 = if (enable) 12 else 0;
    // hudDrawRaceHud
    _ = x86.call(0x460BD3, @intFromPtr(draw_fn));
    _ = x86.call(0x460E6B, @intFromPtr(draw_fn));
    _ = x86.call(0x460ED9, @intFromPtr(draw_fn));
    // hudDrawRaceResults
    _ = x86.call(0x46252F, @intFromPtr(draw_fn));
    _ = x86.call(0x462660, @intFromPtr(draw_fn));
    _ = mem.write(0x4623D7, u8, end_race_timer_offset + 91);
    _ = mem.write(0x4623F1, u8, end_race_timer_offset + 105);
    _ = mem.write(0x46240B, u8, end_race_timer_offset + 115);
    _ = mem.write(0x46241E, u8, end_race_timer_offset + 125);
    _ = mem.write(0x46242D, u8, end_race_timer_offset + 135);
}

// PLANET CUTSCENES

fn PatchPlanetCutscenes(enable: bool) void {
    if (enable) {
        _ = x86.nop_until(0x45753D, comptime 0x45753D + 5);
    } else {
        _ = x86.call(0x45753D, @intFromPtr(rvi.swrVideo_PlayVideoFile));
    }
}

// PODIUM CUTSCENE

// force game to use in-built debug feature to fast scroll through podium cutscene
fn PatchPodiumCutscene(enable: bool) void {
    // see end of fn_43CEB0
    var buf: [2]u8 = undefined;
    buf = if (enable) .{ 0x90, 0x90 } else .{ 0x75, 0x09 };
    _ = mem.write_bytes(0x43D48C, &buf, 2); // jnz+09
    buf = if (enable) .{ 0x90, 0x90 } else .{ 0x74, 0x29 };
    _ = mem.write_bytes(0x43D495, &buf, 2); // jz+29
    buf = if (enable) .{ 0x90, 0x90 } else .{ 0x7E, 0x20 };
    _ = mem.write_bytes(0x43D49E, &buf, 2); // jle+20
    buf = if (enable) .{ 0x90, 0x90 } else .{ 0x74, 0x0A };
    _ = mem.write_bytes(0x43D4B4, &buf, 2); // jz+0A
}

// VIEWPORT

// eliminate the extra undrawn pixel on bottom and right of screen
// tradeoff - slight cutoff for stuff placed right along edge,
//   could possibly be mitigated by adjusting quad scale on per-sprite basis
fn PatchViewportEdges(enable: bool) void {
    const h: u8 = if (enable) 0x90 else 0x48; // dec eax = height
    const w: u8 = if (enable) 0x90 else 0x49; // dec ecx = width
    _ = mem.write(0x44F610, u8, h);
    _ = mem.write(0x44F611, u8, w);
}

// GAME CHEATS

// TODO: add quick toggle to menus
// TODO: fix sound bug when activating cy yunga cheat (use sound 45)
// TODO: setting to actually enable the jinn/cy patches?

fn PatchJinnReesoCheat(enable: bool) void {
    _ = x86.call(0x4105DD, @intFromPtr(if (enable) &ToggleJinnReeso else rv.Vehicle_EnableJinnReeso));
}

fn ToggleJinnReeso() callconv(.C) void {
    const state = struct {
        var initialized: bool = false;
        var on: bool = false;
    };
    if (!state.initialized) {
        state.on = mem.read(rv.JINN_REESO_METADATA_ADDR + 4, u32) == 299;
        state.initialized = true;
    }

    state.on = !state.on;
    if (state.on) {
        rv.Vehicle_EnableJinnReeso();
    } else {
        DisableJinnReeso();
    }
}

fn DisableJinnReeso() callconv(.C) void {
    //VehicleMetadata = 0x4C28A0
    _ = mem.write(comptime rv.JINN_REESO_METADATA_ADDR + 0x04, u32, 16); // Podd
    _ = mem.write(comptime rv.JINN_REESO_METADATA_ADDR + 0x08, u32, 18); // MAlt
    _ = mem.write(comptime rv.JINN_REESO_METADATA_ADDR + 0x0C, u32, 263); // PartLo
    _ = mem.write(comptime rv.JINN_REESO_METADATA_ADDR + 0x30, u32, 92); // Pupp
    _ = mem.write(comptime rv.JINN_REESO_METADATA_ADDR + 0x14, u32, 0x4C397C); // PtrFirst
    _ = mem.write(comptime rv.JINN_REESO_METADATA_ADDR + 0x18, u32, 0x4C3964); // PtrLast
    //MysteryStruct = 0x4C73E8
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x0C, u32, 0x40A8A3D7);
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x24, u32, 0x3FA147AE);
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x28, u32, 0x4043D70A);
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x2C, u32, 0xBF3D70A4);
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x30, u32, 0xC0147AE1);
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x34, u32, 0xC06F5C29);
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x38, u32, 0x3EF0A3D7);
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x3C, u32, 0x401851EC);
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x40, u32, 0x00000000);
    _ = mem.write(comptime rv.JINN_REESO_MYSTERY_ADDR + 0x44, u32, 0x00000000);
}

fn PatchCyYungaCheat(enable: bool) void {
    _ = x86.call(0x410578, @intFromPtr(if (enable) &ToggleCyYunga else rv.Vehicle_EnableCyYunga));
}

fn ToggleCyYunga() callconv(.C) void {
    const state = struct {
        var initialized: bool = false;
        var on: bool = false;
    };
    if (!state.initialized) {
        state.on = mem.read(rv.CY_YUNGA_METADATA_ADDR + 4, u32) == 301;
        state.initialized = true;
    }

    state.on = !state.on;
    if (state.on) {
        rv.Vehicle_EnableCyYunga();
    } else {
        DisableCyYunga();
    }
}

fn DisableCyYunga() callconv(.C) void {
    //VehicleMetadata = 0x4C2B78
    _ = mem.write(comptime rv.CY_YUNGA_METADATA_ADDR + 0x04, u32, 46); // Podd
    _ = mem.write(comptime rv.CY_YUNGA_METADATA_ADDR + 0x08, u32, 45); // MAlt
    _ = mem.write(comptime rv.CY_YUNGA_METADATA_ADDR + 0x0C, u32, 277); // PartLo
    _ = mem.write(comptime rv.CY_YUNGA_METADATA_ADDR + 0x30, u32, 108); // Pupp
    _ = mem.write(comptime rv.CY_YUNGA_METADATA_ADDR + 0x14, u32, 0x4C36C4); // PtrFirst
    _ = mem.write(comptime rv.CY_YUNGA_METADATA_ADDR + 0x18, u32, 0x4C36A8); // PtrLast
    //MysteryStruct = 0x4C79D0
    _ = mem.write(comptime rv.CY_YUNGA_MYSTERY_ADDR + 0x30, u32, 0x00000000);
    _ = mem.write(comptime rv.CY_YUNGA_MYSTERY_ADDR + 0x34, u32, 0x3F7AE148);
    _ = mem.write(comptime rv.CY_YUNGA_MYSTERY_ADDR + 0x38, u32, 0x3F6E147B);
    _ = mem.write(comptime rv.CY_YUNGA_MYSTERY_ADDR + 0x3C, u32, 0x3F851EB8);
    _ = mem.write(comptime rv.CY_YUNGA_MYSTERY_ADDR + 0x40, u32, 0x3F8A3D71);
    _ = mem.write(comptime rv.CY_YUNGA_MYSTERY_ADDR + 0x44, u32, 0x3DCCCCCD);
}

fn PatchCyYungaCheatAudio(enable: bool) void {
    const id: u8 = if (enable) 0x2D else 0xFF;
    _ = mem.write(comptime 0x41057D + 0x01, u8, id);
}

// FAST COUNTDOWN

// TODO: settings for count length, enable

const FastCountdown = struct {
    var h_s_enable: ?SettingHandle = null;
    var h_s_duration: ?SettingHandle = null;

    var CountDuration: f32 = 1.0;
    var CountRatio: f32 = 3 / 1.0;
    var CountDif: f32 = 3 - 1.0;
    var CurrentFrametime: f64 = 1 / 24;

    fn update() void {
        CurrentFrametime = CountRatio * rti.FRAMETIME_64.*;
    }

    fn init(duration: f32) void {
        CountDuration = std.math.clamp(duration, 0.05, 3.00);
        CountRatio = 3 / CountDuration;
        CountDif = 3 - CountDuration;
    }

    fn patch(enable: bool) void {
        const addr: usize = if (enable) @intFromPtr(&CurrentFrametime) else rti.FRAMETIME_64_ADDR;
        const prerace_max_time: u32 = if (enable) @bitCast(9.10 + CountDif) else 0x4111999A; // 9.10
        const boost_window_min: u32 = if (enable) @bitCast(0.05 * CountRatio) else 0x3D4CCCCD; // 0.05
        const boost_window_max: u32 = if (enable) @bitCast(0.30 * CountRatio) else 0x3E99999A; // 0.30
        _ = mem.write(0x45E628, usize, addr);
        _ = mem.write(0x45E2D5, u32, prerace_max_time);
        _ = mem.write(0x4AD254, u32, boost_window_min);
        _ = mem.write(0x4AD258, u32, boost_window_max);
    }

    fn settingsLoad(gf: *GlobalFn) void {
        const enable = gf.SettingGetB("qol", "fast_countdown_enable") orelse false;
        const duration = gf.SettingGetF("qol", "fast_countdown_duration") orelse 1.0;
        if (enable) init(duration);
        patch(enable);
    }
};

// PRACTICE/STATISTICAL DATA

const race = struct {
    const stat_x: i16 = 192;
    const stat_y: i16 = 48;
    const stat_h: i16 = 12;
    const stat_col: ?u32 = 0xFFFFFFFF;
    var this_position: spatial.Pos3D = .{}; // TODO: convert to racer types & update with racer fns
    var prev_position: spatial.Pos3D = .{};
    var top_speed: f32 = 0;
    var total_distance: f32 = 0;
    var total_boosts: u32 = 0;
    var total_boost_duration: f32 = 0;
    var total_boost_distance: f32 = 0;
    var total_boost_ratio: f32 = 0;
    var total_underheat: f32 = 0;
    var total_overheat: f32 = 0;
    var first_boost_time: f32 = 0;
    var fire_finish_duration: f32 = 0;
    var last_boost_started: f32 = 0;
    var last_boost_started_total: f32 = 0;
    var last_underheat_started: f32 = 0;
    var last_underheat_started_total: f32 = 0;
    var last_overheat_started: f32 = 0;
    var last_overheat_started_total: f32 = 0;
    var avg_boost_duration: f32 = 0;
    var avg_boost_distance: f32 = 0;
    var avg_speed: f32 = 0;

    fn reset() void {
        this_position = .{};
        prev_position = .{};
        top_speed = 0;
        total_distance = 0;
        total_boosts = 0;
        total_boost_duration = 0;
        total_boost_distance = 0;
        total_boost_ratio = 0;
        total_underheat = 0;
        total_overheat = 0;
        first_boost_time = 0;
        fire_finish_duration = 0;
        last_boost_started = 0;
        last_boost_started_total = 0;
        last_underheat_started = 0;
        last_underheat_started_total = 0;
        last_overheat_started = 0;
        last_overheat_started_total = 0;
        avg_boost_duration = 0;
        avg_boost_distance = 0;
        avg_speed = 0;
    }

    fn set_motion(time: f32, speed: f32, distance: f32) void {
        total_distance += distance;
        if (time > 0) avg_speed = total_distance / time;
        if (speed > top_speed) top_speed = speed;
    }

    fn set_last_boost_start(time: f32) void {
        total_boosts += 1;
        last_boost_started_total = total_boost_duration;
        last_boost_started = time;
        if (first_boost_time == 0) first_boost_time = time;
    }

    fn set_total_boost(time: f32, distance: f32) void {
        total_boost_duration = last_boost_started_total + time - last_boost_started;
        if (time > 0) total_boost_ratio = total_boost_duration / time;
        total_boost_distance += distance;
        if (total_boosts > 0) {
            avg_boost_duration = total_boost_duration / @as(f32, @floatFromInt(total_boosts));
            avg_boost_distance = total_boost_distance / @as(f32, @floatFromInt(total_boosts));
        }
    }

    fn set_last_underheat_start(time: f32) void {
        last_underheat_started_total = total_underheat;
        last_underheat_started = time;
    }

    fn set_total_underheat(time: f32) void {
        total_underheat = last_underheat_started_total + time - last_underheat_started;
    }

    fn set_last_overheat_start(time: f32) void {
        last_overheat_started_total = total_overheat;
        last_overheat_started = time;
    }

    fn set_total_overheat(time: f32) void {
        total_overheat = last_overheat_started_total + time - last_overheat_started;
    }

    fn set_fire_finish_duration(time: f32) void {
        fire_finish_duration = time - last_overheat_started;
    }

    fn update_position() void {
        prev_position = this_position;
        this_position = @as(*spatial.Pos3D, @ptrCast(&re.Test.PLAYER.*.transform.T)).*; // FIXME
    }
};

const s_head = rt.MakeTextHeadStyle(.Default, true, null, .Center, .{rto.ToggleShadow}) catch "";

fn RenderRaceResultHeader(gf: *GlobalFn, i: i16, comptime fmt: []const u8, args: anytype) void {
    _ = gf.GDrawText(.Default, rt.MakeText(640 - race.stat_x, race.stat_y + i * race.stat_h, fmt, args, race.stat_col, s_head) catch null);
}

const s_stat = rt.MakeTextHeadStyle(.Default, true, null, .Right, .{rto.ToggleShadow}) catch "";

fn RenderRaceResultStat(gf: *GlobalFn, i: i16, label: [*:0]const u8, comptime value_fmt: []const u8, value_args: anytype) void {
    _ = gf.GDrawText(.Default, rt.MakeText(640 - race.stat_x - 8, race.stat_y + i * race.stat_h, "{s}", .{label}, race.stat_col, s_stat) catch null);
    _ = gf.GDrawText(.Default, rt.MakeText(640 - race.stat_x + 8, race.stat_y + i * race.stat_h, value_fmt, value_args, race.stat_col, null) catch null);
}

fn RenderRaceResultStatU(gf: *GlobalFn, i: i16, label: [*:0]const u8, value: u32) void {
    RenderRaceResultStat(gf, i, label, "{d: <7}", .{value});
}

fn RenderRaceResultStatF(gf: *GlobalFn, i: i16, label: [*:0]const u8, value: f32) void {
    RenderRaceResultStat(gf, i, label, "{d:4.3}", .{value});
}

fn RenderRaceResultStatTime(gf: *GlobalFn, i: i16, label: [*:0]const u8, time: f32) void {
    const t = timing.RaceTimeFromFloat(time);
    RenderRaceResultStat(gf, i, label, "{d}:{d:0>2}.{d:0>3}", .{ t.min, t.sec, t.ms });
}

const s_upg_full = rt.MakeTextStyle(.Green, null, .{}) catch "";
const s_upg_dmg = rt.MakeTextStyle(.Red, null, .{}) catch "";

fn RenderRaceResultStatUpgrade(gf: *GlobalFn, i: i16, cat: u8, lv: u8, hp: u8) void {
    RenderRaceResultStat(gf, i, rv.UpgradeNames[cat], "{s}{d:0>3} ~1{s}", .{
        if (hp < 255) s_upg_dmg else s_upg_full, hp, rv.PartNameS(cat)[lv],
    });
}

// QUICK RACE MENU

// TODO: labels next to tracks to indicate planet (or circuit)
// TODO: generalize menuing and add hooks to let plugins add pages to the menu
// TODO: make it wait till the end of the pause scroll-in, so that the scroll-out
// is always the same as a normal pause
// TODO: add options/differentiation for tournament mode races, and also maybe
// set the global 'in tournament mode' accordingly
// TODO: set upgrade healths (hold interact to set health instead of level)

const QuickRaceMenuInput = extern struct {
    kb: VIRTUAL_KEY,
    xi: XINPUT_GAMEPAD_BUTTON_INDEX,
    state: st.ActiveState = undefined,
};

const QuickRaceMenu = extern struct {
    var h_s_fps_default: ?SettingHandle = null;

    const open_threshold: f32 = 0.75;
    var menu_active: st.ActiveState = .Off;
    var initialized: bool = false;
    // TODO: figure out if these can be removed, currently blocked by quick race menu callbacks
    var gs: *GlobalSt = undefined;
    var gf: *GlobalFn = undefined;

    var FpsTimer: timing.TimeSpinlock = .{};

    const values = extern struct {
        var fps: i32 = 24;
        var vehicle: i32 = 0;
        var track: i32 = 0;
        var up_lv = [_]i32{0} ** 7;
        var up_hp = [_]i32{0} ** 7;
        var mirror: i32 = 0; // hang
        var laps: i32 = 1; // hang, 1-5
        var racers: i32 = 1; // 0x50C558, 1-12 normally, up to 20 without crash?
        var ai_speed: i32 = 2; // hang, 1-3
        //var winnings_split: i32 = 1; // hang
    };

    var inputs = [_]QuickRaceMenuInput{
        .{ .kb = .UP, .xi = .DPAD_UP },
        .{ .kb = .DOWN, .xi = .DPAD_DOWN },
        .{ .kb = .LEFT, .xi = .DPAD_LEFT },
        .{ .kb = .RIGHT, .xi = .DPAD_RIGHT },
        .{ .kb = .RETURN, .xi = .A }, // confirm/activate
        .{ .kb = .SPACE, .xi = .START }, // quick confirm
        .{ .kb = .HOME, .xi = .LEFT_SHOULDER }, // NU
        .{ .kb = .END, .xi = .RIGHT_SHOULDER }, // MU
    };

    fn get_input(comptime input: *QuickRaceMenuInput) InputGetFnType {
        const s = struct {
            fn gi(i: st.ActiveState) callconv(.C) bool {
                return input.state == i;
            }
        };
        return &s.gi;
    }

    inline fn update_input() void {
        for (&inputs) |*i|
            i.state.update(gf.InputGetKbRaw(i.kb).on() or gf.InputGetXInputButton(i.xi).on());
    }

    var data: Menu = .{
        .title = "Quick Race",
        .items = .{ .it = @ptrCast(&QuickRaceMenuItems), .len = QuickRaceMenuItems.len },
        .inputs = .{
            .cb = &[_]InputGetFnType{
                get_input(&inputs[4]), get_input(&inputs[5]),
                get_input(&inputs[6]), get_input(&inputs[7]),
            },
            .len = 3,
        },
        .callback = QuickRaceCallback,
        .y_scroll = .{
            .scroll_time = 0.75,
            .scroll_units = 18,
            .input_dec = get_input(&inputs[0]),
            .input_inc = get_input(&inputs[1]),
        },
        .x_scroll = .{
            .scroll_time = 0.75,
            .scroll_units = 18,
            .input_dec = get_input(&inputs[2]),
            .input_inc = get_input(&inputs[3]),
        },
    };

    fn load_race() void {
        FpsTimer.SetPeriod(@intCast(values.fps));
        _ = mem.write(0xE35A84, u8, @as(u8, @intCast(values.vehicle))); // file slot 0 - character
        var hang = re.Manager.entity(.Hang, 0);
        hang.VehiclePlayer = @intCast(values.vehicle);
        hang.Track = @intCast(values.track);
        hang.Circuit = rtr.TrackCircuitIdMap[@intCast(values.track)];
        hang.Mirror = @intCast(values.mirror);
        hang.Laps = @intCast(values.laps);
        hang.AISpeed = @intCast(values.ai_speed + 1);
        hang.Racers = @intCast(values.racers);
        _ = mem.write(0x50C558, u8, @as(u8, @intCast(values.racers))); // for cantina
        for (0..7) |i| {
            rrd.PLAYER.*.pFile.upgrade_lv[i] = @intCast(values.up_lv[i]);
            rrd.PLAYER.*.pFile.upgrade_hp[i] = @intCast(values.up_hp[i]);
        }

        const jdge = re.Manager.entity(.Jdge, 0);
        re.Jdge.TriggerLoad_InRace(jdge, re.M_RSTR);
        close();
    }

    // TODO: repurpose to run every EventJdgeBegn, maybe add different init if
    // that introduces issues with state loop
    fn init() void {
        const hang = re.Manager.entity(.Hang, 0);
        values.vehicle = hang.VehiclePlayer;
        values.track = hang.Track;
        values.mirror = hang.Mirror;
        values.laps = hang.Laps;
        values.racers = hang.Racers;
        values.ai_speed = hang.AISpeed - 1;
        //values.ai_speed = hang.Winnings;
        for (0..7) |i| {
            values.up_lv[i] = rrd.PLAYER.*.pFile.upgrade_lv[i];
            values.up_hp[i] = rrd.PLAYER.*.pFile.upgrade_hp[i];
        }

        initialized = true;
    }

    fn open() void {
        rg.PAUSE_SCROLLINOUT.* = open_threshold;
        if (!gf.GFreezeOn()) return;
        //rf.swrSound_PlaySound(78, 6, 0.25, 1.0, 0);
        data.idx = 0;
        menu_active.update(true);
    }

    fn close() void {
        if (!gf.GFreezeOff()) return;
        rso.swrSound_PlaySound(77, 6, 0.25, 1.0, 0);
        rg.PAUSE_STATE.* = 3;
        menu_active.update(false);
    }

    fn update() void {
        if (gs.in_race == .JustOn)
            init();

        if (!gs.in_race.on() or !initialized) return;

        defer {
            if (menu_active.on()) data.UpdateAndDraw();
            menu_active.update(menu_active.on());
        }

        const upi = QolState.input_unpause.gets();
        if (menu_active.on() and upi == .JustOn)
            return close();

        const pi = QolState.input_pause.gets();
        if (rg.PAUSE_STATE.* == 2 and pi == .JustOn)
            return open();
        if (rg.PAUSE_STATE.* == 2 and rg.PAUSE_SCROLLINOUT.* >= open_threshold and pi == .On)
            return open();
    }

    fn settingsLoad(v: *GlobalFn) void {
        const fps_default = v.SettingGetU("qol", "fps_limiter_default").?;
        QuickRaceMenu.FpsTimer.SetPeriod(fps_default);
        QuickRaceMenu.values.fps = @intCast(fps_default);
    }
};

const QuickRaceMenuItems = [_]mi.MenuItem{
    mi.MenuItemRange(&QuickRaceMenu.values.fps, "FPS", 10, 500, true, &QuickRaceFpsCallback),
    mi.MenuItemSpacer(),
    mi.MenuItemList(&QuickRaceMenu.values.vehicle, "Vehicle", &rv.VehicleNames, true, null),
    // FIXME: maybe change to menu order?
    mi.MenuItemList(&QuickRaceMenu.values.track, "Track", &rtr.TracksById, true, &QuickRaceTrackCallback),
    mi.MenuItemSpacer(),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[0], rv.UpgradeNames[0], rv.PartNameS(0), false, &QuickRaceUpgradeCallback),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[1], rv.UpgradeNames[1], rv.PartNameS(1), false, &QuickRaceUpgradeCallback),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[2], rv.UpgradeNames[2], rv.PartNameS(2), false, &QuickRaceUpgradeCallback),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[3], rv.UpgradeNames[3], rv.PartNameS(3), false, &QuickRaceUpgradeCallback),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[4], rv.UpgradeNames[4], rv.PartNameS(4), false, &QuickRaceUpgradeCallback),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[5], rv.UpgradeNames[5], rv.PartNameS(5), false, &QuickRaceUpgradeCallback),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[6], rv.UpgradeNames[6], rv.PartNameS(6), false, &QuickRaceUpgradeCallback),
    mi.MenuItemSpacer(),
    mi.MenuItemToggle(&QuickRaceMenu.values.mirror, "Mirror"),
    mi.MenuItemRange(&QuickRaceMenu.values.laps, "Laps", 1, 5, true, null),
    mi.MenuItemRange(&QuickRaceMenu.values.racers, "Racers", 1, 12, true, null),
    mi.MenuItemList(&QuickRaceMenu.values.ai_speed, "AI Speed", &[_][*:0]const u8{ "Slow", "Average", "Fast" }, true, null),
    //mi.MenuItemList(&QuickRaceMenu.values.winnings_split, "Winnings", &[_][]const u8{ "Fair", "Skilled", "Winner Takes All" }, true),
    mi.MenuItemSpacer(),
    mi.MenuItemButton("Race!", &QuickRaceConfirm),
};

fn QuickRaceCallback(m: *Menu) callconv(.C) bool {
    var result = false;
    if (m.inputs.cb) |cb| {
        // confirm from anywhere
        if (cb[1](.JustOn) and QuickRaceMenu.menu_active == .On) {
            QuickRaceMenu.load_race();
            return false;
        }
    }
    return result;
}

fn QuickRaceUpgradeCallback(m: *Menu) callconv(.C) bool {
    if (m.inputs.cb) |cb| {
        // set all to NU
        if (cb[2](.JustOn)) {
            QuickRaceMenu.values.up_lv = comptime [_]i32{0} ** 7;
            return true;
        }
        // set all to MU
        if (cb[3](.JustOn)) {
            QuickRaceMenu.values.up_lv = comptime [_]i32{5} ** 7;
            return true;
        }
    }
    return false;
}

// TODO: higher options if moving cap to 1000fps later
// TODO: user-defined preset, maybe
const QuickRaceFpsPresets = [_]i32{ 24, 30, 48, 60, 120, 144, 165, 240, 360, 480 };

fn QuickRaceFpsCallback(m: *Menu) callconv(.C) bool {
    if (m.inputs.cb) |cb| {
        // scroll presets
        if (cb[2](.JustOn)) {
            QuickRaceMenu.values.fps = blk: {
                for (0..QuickRaceFpsPresets.len) |i| {
                    const val = QuickRaceFpsPresets[QuickRaceFpsPresets.len - i - 1];
                    if (val < QuickRaceMenu.values.fps) break :blk val;
                }
                break :blk QuickRaceMenuItems[0].min;
            };
            return true;
        }
        if (cb[3](.JustOn)) {
            QuickRaceMenu.values.fps = blk: {
                for (QuickRaceFpsPresets) |val|
                    if (val > QuickRaceMenu.values.fps) break :blk val;
                break :blk QuickRaceMenuItems[0].max;
            };
            return true;
        }

        // save without restarting
        if (cb[0](.JustOn) and QuickRaceMenu.gs.practice_mode) {
            QuickRaceMenu.FpsTimer.SetPeriod(@intCast(QuickRaceMenu.values.fps));
            rso.swrSound_PlaySoundMacro(0x2D);
        }
    }
    return false;
}

// TODO: circuit-based presets, if/when circuit order added
// TODO: highlight color changing depending on planet?
const QuickRaceTrackPresets = [_]i32{ 0, 2, 6, 9, 12, 16, 19, 22 };

fn QuickRaceTrackCallback(m: *Menu) callconv(.C) bool {
    if (m.inputs.cb) |cb| {
        // scroll presets
        if (cb[2](.JustOn)) {
            QuickRaceMenu.values.track = blk: {
                for (0..QuickRaceTrackPresets.len) |i| {
                    const val = QuickRaceTrackPresets[QuickRaceTrackPresets.len - i - 1];
                    if (val < QuickRaceMenu.values.track) break :blk val;
                }
                break :blk comptime QuickRaceTrackPresets[QuickRaceTrackPresets.len - 1];
            };
            return true;
        }
        if (cb[3](.JustOn)) {
            QuickRaceMenu.values.track = blk: {
                for (QuickRaceTrackPresets) |val|
                    if (val > QuickRaceMenu.values.track) break :blk val;
                break :blk comptime QuickRaceTrackPresets[0];
            };
            return true;
        }
    }
    return false;
}

fn QuickRaceConfirm(m: *Menu) callconv(.C) bool {
    if (m.inputs.cb) |cb| {
        if (cb[0](.JustOn)) {
            QuickRaceMenu.load_race();
        }
    }
    return false;
}

fn settingsInit(gf: *GlobalFn) void {
    const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "qol", null);
    QolState.h_s_section = section;

    QolState.h_s_quickstart =
        gf.ASettingOccupy(section, "quick_restart_enable", .B, .{ .b = false }, null, null);
    QolState.h_s_quickrace =
        gf.ASettingOccupy(section, "quick_race_menu_enable", .B, .{ .b = false }, null, null);
    QolState.h_s_default_racers =
        gf.ASettingOccupy(section, "default_racers", .U, .{ .u = 12 }, null, null);
    QolState.h_s_default_laps =
        gf.ASettingOccupy(section, "default_laps", .U, .{ .u = 3 }, null, null);
    QolState.h_s_ms_timer =
        gf.ASettingOccupy(section, "ms_timer_enable", .B, .{ .b = false }, null, null);
    QolState.h_s_fps_limiter =
        gf.ASettingOccupy(section, "fps_limiter_enable", .B, .{ .b = false }, null, null);
    QolState.h_s_skip_planet_cutscenes =
        gf.ASettingOccupy(section, "skip_planet_cutscenes", .B, .{ .b = false }, null, null);
    QolState.h_s_skip_podium_cutscene =
        gf.ASettingOccupy(section, "skip_podium_cutscene", .B, .{ .b = false }, null, null);
    QolState.h_s_fix_viewport_edges =
        gf.ASettingOccupy(section, "fix_viewport_edges", .B, .{ .b = false }, null, null);

    FastCountdown.h_s_enable =
        gf.ASettingOccupy(section, "fast_countdown_enable", .B, .{ .b = false }, null, null);
    FastCountdown.h_s_duration =
        gf.ASettingOccupy(section, "fast_countdown_duration", .F, .{ .f = 1.0 }, null, null);

    QuickRaceMenu.h_s_fps_default =
        gf.ASettingOccupy(section, "fps_limiter_default", .U, .{ .u = 24 }, null, null);
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
    _ = w32wm.ShowCursor(0); // cursor fix
    QolState.HandleSettings(gf); // FIXME: convert to settingsInit stuff

    QuickRaceMenu.gs = gs;
    QuickRaceMenu.gf = gf;
    QuickRaceMenu.settingsLoad(gf); // FIXME: convert to settingsInit stuff
    //QuickRaceMenu.FpsTimer.Start();

    PatchJinnReesoCheat(true);
    PatchCyYungaCheat(true);
    PatchCyYungaCheatAudio(true);

    FastCountdown.settingsLoad(gf); // FIXME: convert to settingsInit stuff

    settingsInit(gf);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // TODO: look into using in-game default setter, see fn_45BD90
    // TODO: change annodue setting to i32 for both, also look into anywhere
    // else like this that might have been affected by new Hang stuff

    if (QolState.default_laps >= 1 and QolState.default_laps <= 5)
        re.Manager.entity(.Hang, 0).Laps = @intCast(QolState.default_laps);

    if (QolState.default_racers >= 1 and QolState.default_racers <= 12)
        _ = mem.write(0x50C558, i8, @as(i8, @intCast(QolState.default_racers))); // racers
}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    QuickRaceMenu.FpsTimer.End();
    QuickRaceMenu.close();

    PatchJinnReesoCheat(false);
    PatchCyYungaCheat(false);
    PatchCyYungaCheatAudio(false);

    FastCountdown.patch(false);
}

// HOOKS

export fn OnSettingsLoad(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    QolState.HandleSettings(gf);
    FastCountdown.settingsLoad(gf);
}

export fn InputUpdateB(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    QolState.UpdateInput(gf);
    QuickRaceMenu.update_input();
}

export fn InputUpdateKeyboardA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // map xinput start to esc
    const start_on: u32 = @intFromBool(QolState.input_pause.gets() == .On);
    const start_just_on: u32 = @intFromBool(QolState.input_pause.gets() == .JustOn);
    _ = mem.write(ri.RAW_STATE_ON + 4, u32, start_on);
    _ = mem.write(ri.RAW_STATE_JUST_ON + 4, u32, start_just_on);
}

export fn TimerUpdateB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // TODO: confirm tabbed_in is actually needed here, possibly move to global state
    const tabbed_in: bool = rg.GUI_STOPPED.* == 0;
    if (gs.in_race.on() and tabbed_in and QolState.fps_limiter)
        QuickRaceMenu.FpsTimer.Sleep();
}

export fn TimerUpdateA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    FastCountdown.update();
}

// FIXME: settings toggles for both of these
// FIXME: probably want this mid-engine update, immediately before Jdge gets
// processed? (a fn in EngineUpdateStage14 iirc)
export fn EarlyEngineUpdateB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // Quick Restart
    if (gs.in_race.on() and
        QolState.quickstart and
        !QuickRaceMenu.menu_active.on() and
        ((QolState.input_quickstart.gets().on() and QolState.input_pause.gets() == .JustOn) or
        (QolState.input_quickstart.gets() == .JustOn and QolState.input_pause.gets().on())))
    {
        const jdge = re.Manager.entity(.Jdge, 0);
        rso.swrSound_PlaySound(77, 6, 0.25, 1.0, 0);
        re.Jdge.TriggerLoad_InRace(jdge, re.M_RSTR);
        return; // skip quick race menu
    }

    // Quick Race Menu
    if (QolState.quickrace)
        QuickRaceMenu.update();
}

// FIXME: investigate - used to be TextRenderB, but that doesn't run every frame
// however, the text flushing DOES run on those frames, apparently from a different callsite
export fn EarlyEngineUpdateA(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (gs.in_race.on()) {
        if (gs.race_state_new and gs.race_state == .PreRace) race.reset();

        const total_time: f32 = rrd.PLAYER.*.time.total;

        if (gs.race_state == .Countdown) {
            race.update_position();
        }

        if (gs.race_state == .Racing or (gs.race_state_new and gs.race_state == .PostRace)) {
            const speed = re.Test.PLAYER.*.speed;
            race.update_position();
            const this_distance = race.this_position.distance(&race.prev_position);
            race.set_motion(total_time, speed, this_distance);

            if (gs.player.boosting == .JustOn) race.set_last_boost_start(total_time);
            if (gs.player.boosting.on()) race.set_total_boost(total_time, this_distance);
            if (gs.player.boosting == .JustOff) race.set_total_boost(total_time, this_distance);

            if (gs.player.underheating == .JustOn) race.set_last_underheat_start(total_time);
            if (gs.player.underheating.on()) race.set_total_underheat(total_time);
            if (gs.player.underheating == .JustOff) race.set_total_underheat(total_time);

            if (gs.player.overheating == .JustOn) race.set_last_overheat_start(total_time);
            if (gs.player.overheating.on()) race.set_total_overheat(total_time);
            if (gs.player.overheating == .JustOff) race.set_total_overheat(total_time);
            if (gs.player.overheating == .JustOff) race.set_fire_finish_duration(total_time);
        }

        if (gs.race_state == .PostRace and !gf.GHideRaceUIIsOn()) {
            const upg_postfix = if (gs.player.upgrades) "" else "  NU";
            RenderRaceResultHeader(gf, 0, "{d:>2.0}/{s}{s}", .{
                gs.fps_avg,
                rv.PartNamesShort[gs.player.upgrades_lv[0]],
                upg_postfix,
            });

            for (0..7) |i| RenderRaceResultStatUpgrade(
                gf,
                2 + @as(u8, @truncate(i)),
                @as(u8, @truncate(i)),
                gs.player.upgrades_lv[i],
                gs.player.upgrades_hp[i],
            );

            RenderRaceResultStatF(gf, 10, "Top Speed", race.top_speed);
            RenderRaceResultStatF(gf, 11, "Avg. Speed", race.avg_speed);
            RenderRaceResultStatF(gf, 12, "Distance", race.total_distance);
            RenderRaceResultStatU(gf, 13, "Deaths", gs.player.deaths);
            RenderRaceResultStatTime(gf, 20, "First Boost", race.first_boost_time);
            RenderRaceResultStatTime(gf, 21, "Underheat Time", race.total_underheat);
            RenderRaceResultStatTime(gf, 22, "Fire Finish", race.fire_finish_duration);
            RenderRaceResultStatTime(gf, 23, "Overheat Time", race.total_overheat);
            RenderRaceResultStatU(gf, 14, "Boosts", race.total_boosts);
            RenderRaceResultStatTime(gf, 15, "Boost Time", race.total_boost_duration);
            RenderRaceResultStatTime(gf, 16, "Avg. Boost Time", race.avg_boost_duration);
            RenderRaceResultStatF(gf, 17, "Boost Distance", race.total_boost_distance);
            RenderRaceResultStatF(gf, 18, "Avg. Boost Distance", race.avg_boost_distance);
            RenderRaceResultStatF(gf, 19, "Boost Ratio", race.total_boost_ratio);
        }
    }
}

export fn MapRenderB(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // TODO: move to core? since it only matters with running annodue
    rt.TEXT_HIRES_FLAG.* = 0;
}
