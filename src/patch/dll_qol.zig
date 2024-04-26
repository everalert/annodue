const Self = @This();

const std = @import("std");
const win = std.os.windows;
const w32 = @import("zigwin32");
const w32wm = w32.ui.windows_and_messaging;
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;
const XINPUT_GAMEPAD_BUTTON_INDEX = @import("core/Input.zig").XINPUT_GAMEPAD_BUTTON_INDEX;

const GlobalSt = @import("core/Global.zig").GlobalState;
const GlobalFn = @import("core/Global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("core/Global.zig").PLUGIN_VERSION;

const debug = @import("core/Debug.zig");

const timing = @import("util/timing.zig");
const Menu = @import("util/menu.zig").Menu;
const InputGetFnType = @import("util/menu.zig").InputGetFnType;
const mi = @import("util/menu_item.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");
const st = @import("util/active_state.zig");

const r = @import("util/racer.zig");
const rf = r.functions;
const rc = r.constants;
const rt = r.text;
const rto = rt.TextStyleOpts;

const InputMap = @import("core/Input.zig").InputMap;
const ButtonInputMap = @import("core/Input.zig").ButtonInputMap;
const AxisInputMap = @import("core/Input.zig").AxisInputMap;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// - fix: remove double mouse cursor
// - fix: pause game with xinput controller (maps Start -> Esc)
// - feat: quick restart
//     - CONTROLS:          F1+Esc          Back+Start
// - feat: quick race menu
//     - create a new race from inside a race
//     - select pod, track, upgrade stack and other race settings
//     - CONTROLS:          keyboard        xinput
//       Open/Close         Esc             Start           Press during normal pause delay (i.e. double-tap)
//       Navigate           ↑↓→←            D-Pad
//       Interact           Space           A
//       Quick Confirm      Enter           B
//       All Upgrades MIN   Home            LB
//       All Upgrades MAX   End             RB
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
// - feat: custom default number of racers
// - feat: custom default number of laps
// - SETTINGS:
//   quick_restart_enable       bool
//   quick_race_menu_enable     bool
//   ms_timer_enable            bool
//   fps_limiter_enable         bool
//   default_racers             u32     max 12
//   default_laps               u32     max 5

// TODO: dinput controls
// TODO: setting for fps limiter default value
// TODO: global fps limiter
// TODO: figure out wtf to do to manage state through hot-reload etc.
// FIXME: quick race menu stops working after hot reload??

const PLUGIN_NAME: [*:0]const u8 = "QualityOfLife";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const QolState = struct {
    var quickstart: bool = false;
    var quickrace: bool = false;
    var default_racers: u32 = 12;
    var default_laps: u32 = 3;
    var ms_timer: bool = false;
    var fps_limiter: bool = false;
    var skip_planet_cutscenes: bool = false;

    var input_pause_data = ButtonInputMap{ .kb = .ESCAPE, .xi = .START };
    var input_quickstart_data = ButtonInputMap{ .kb = .F1, .xi = .BACK };
    var input_pause = input_pause_data.inputMap();
    var input_quickstart = input_quickstart_data.inputMap();
};

fn QolUpdateInput(gf: *GlobalFn) callconv(.C) void {
    QolState.input_pause.update(gf);
    QolState.input_quickstart.update(gf);
}

fn QolHandleSettings(gf: *GlobalFn) callconv(.C) void {
    QolState.quickstart = gf.SettingGetB("qol", "quick_restart_enable") orelse false;
    QolState.quickrace = gf.SettingGetB("qol", "quick_race_menu_enable") orelse false;
    QolState.default_racers = gf.SettingGetU("qol", "default_racers") orelse 12;
    QolState.default_laps = gf.SettingGetU("qol", "default_laps") orelse 3;
    QolState.ms_timer = gf.SettingGetB("qol", "ms_timer_enable") orelse false;
    QolState.fps_limiter = gf.SettingGetB("qol", "fps_limiter_enable") orelse false;
    QolState.skip_planet_cutscenes = gf.SettingGetB("qol", "skip_planet_cutscenes") orelse false;

    if (!QolState.quickrace) QuickRaceMenu.close();
    // FIXME: add these to deinit?
    PatchHudTimerMs(QolState.ms_timer);
    PatchPlanetCutscenes(QolState.skip_planet_cutscenes);
}

// HUD TIMER MS

const end_race_timer_offset: u8 = 12;

// TODO: cleanup
fn PatchHudTimerMs(enable: bool) void {
    if (enable) {
        // hudDrawRaceHud
        _ = x86.call(0x460BD3, @intFromPtr(rf.swrText_DrawTime3));
        _ = x86.call(0x460E6B, @intFromPtr(rf.swrText_DrawTime3));
        _ = x86.call(0x460ED9, @intFromPtr(rf.swrText_DrawTime3));
        // hudDrawRaceResults
        _ = x86.call(0x46252F, @intFromPtr(rf.swrText_DrawTime3));
        _ = x86.call(0x462660, @intFromPtr(rf.swrText_DrawTime3));
        _ = mem.write(0x4623D7, u8, comptime end_race_timer_offset + 91); // 91
        _ = mem.write(0x4623F1, u8, comptime end_race_timer_offset + 105); // 105
        _ = mem.write(0x46240B, u8, comptime end_race_timer_offset + 115); // 115
        _ = mem.write(0x46241E, u8, comptime end_race_timer_offset + 125); // 125
        _ = mem.write(0x46242D, u8, comptime end_race_timer_offset + 135); // 135
    } else {
        // hudDrawRaceHud
        _ = x86.call(0x460BD3, @intFromPtr(rf.swrText_DrawTime2));
        _ = x86.call(0x460E6B, @intFromPtr(rf.swrText_DrawTime2));
        _ = x86.call(0x460ED9, @intFromPtr(rf.swrText_DrawTime2));
        // hudDrawRaceResults
        _ = x86.call(0x46252F, @intFromPtr(rf.swrText_DrawTime2));
        _ = x86.call(0x462660, @intFromPtr(rf.swrText_DrawTime2));
        _ = mem.write(0x4623D7, u8, end_race_timer_offset);
        _ = mem.write(0x4623F1, u8, end_race_timer_offset);
        _ = mem.write(0x46240B, u8, end_race_timer_offset);
        _ = mem.write(0x46241E, u8, end_race_timer_offset);
        _ = mem.write(0x46242D, u8, end_race_timer_offset);
    }
}

// PLANET CUTSCENES

fn PatchPlanetCutscenes(enable: bool) void {
    if (enable) {
        _ = x86.nop_until(0x45753D, comptime 0x45753D + 5);
    } else {
        _ = x86.call(0x45753D, @intFromPtr(rf.swrVideo_PlayVideoFile));
    }
}

// PRACTICE/STATISTICAL DATA

const race = struct {
    const stat_x: i16 = 192;
    const stat_y: i16 = 48;
    const stat_h: u8 = 12;
    const stat_col: ?u32 = 0xFFFFFFFF;
    var total_deaths: u32 = 0;
    var total_boost_duration: f32 = 0;
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

    fn reset() void {
        total_deaths = 0;
        total_boost_duration = 0;
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
    }

    fn set_last_boost_start(time: f32) void {
        last_boost_started_total = total_boost_duration;
        last_boost_started = time;
        if (first_boost_time == 0) first_boost_time = time;
    }

    fn set_total_boost(time: f32) void {
        total_boost_duration = last_boost_started_total + time - last_boost_started;
        total_boost_ratio = total_boost_duration / time;
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
};

const s_head = rt.MakeTextHeadStyle(.Default, true, null, .Center, .{rto.ToggleShadow}) catch "";

fn RenderRaceResultHeader(i: u8, comptime fmt: []const u8, args: anytype) void {
    rt.DrawText(640 - race.stat_x, race.stat_y + i * race.stat_h, fmt, args, race.stat_col, s_head) catch {};
}

const s_stat = rt.MakeTextHeadStyle(.Default, true, null, .Right, .{rto.ToggleShadow}) catch "";

fn RenderRaceResultStat(i: u8, label: [*:0]const u8, comptime value_fmt: []const u8, value_args: anytype) void {
    rt.DrawText(640 - race.stat_x - 8, race.stat_y + i * race.stat_h, "{s}", .{label}, race.stat_col, s_stat) catch {};
    rt.DrawText(640 - race.stat_x + 8, race.stat_y + i * race.stat_h, value_fmt, value_args, race.stat_col, null) catch {};
}

fn RenderRaceResultStatU(i: u8, label: [*:0]const u8, value: u32) void {
    RenderRaceResultStat(i, label, "{d: <7}", .{value});
}

fn RenderRaceResultStatF(i: u8, label: [*:0]const u8, value: f32) void {
    RenderRaceResultStat(i, label, "{d:4.3}", .{value});
}

fn RenderRaceResultStatTime(i: u8, label: [*:0]const u8, time: f32) void {
    const t = timing.RaceTimeFromFloat(time);
    RenderRaceResultStat(i, label, "{d}:{d:0>2}.{d:0>3}", .{ t.min, t.sec, t.ms });
}

const s_upg_full = rt.MakeTextStyle(.Green, null, .{}) catch "";
const s_upg_dmg = rt.MakeTextStyle(.Red, null, .{}) catch "";

fn RenderRaceResultStatUpgrade(i: u8, cat: u8, lv: u8, hp: u8) void {
    RenderRaceResultStat(i, rc.UpgradeCategories[cat], "{s}{d:0>3} ~1{s}", .{
        if (hp < 255) s_upg_dmg else s_upg_full,
        hp,
        rc.UpgradeNames[cat * 6 + lv],
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
    const menu_key: [*:0]const u8 = "QuickRaceMenu";
    var menu_active: bool = false;
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
        .{ .kb = .SPACE, .xi = .A }, // confirm
        .{ .kb = .RETURN, .xi = .B }, // quick confirm
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
        r.WriteEntityValue(.Hang, 0, 0x73, u8, @as(u8, @intCast(values.vehicle)));
        r.WriteEntityValue(.Hang, 0, 0x5D, u8, @as(u8, @intCast(values.track)));
        r.WriteEntityValue(.Hang, 0, 0x5E, u8, rc.TrackCircuitIdMap[@intCast(values.track)]);
        r.WriteEntityValue(.Hang, 0, 0x6E, u8, @as(u8, @intCast(values.mirror)));
        r.WriteEntityValue(.Hang, 0, 0x8F, u8, @as(u8, @intCast(values.laps)));
        r.WriteEntityValue(.Hang, 0, 0x72, u8, @as(u8, @intCast(values.racers))); // also: 0x50C558
        r.WriteEntityValue(.Hang, 0, 0x90, u8, @as(u8, @intCast(values.ai_speed + 1)));
        //r.WriteEntityValue(.Hang, 0, 0x91, u8, @as(u8, @intCast(values.winnings_split)));
        const u = mem.deref(&.{ rc.ADDR_RACE_DATA, 0x0C, 0x41 });
        for (values.up_lv, values.up_hp, 0..) |lv, hp, i| {
            _ = mem.write(u + 0 + i, u8, @as(u8, @intCast(lv)));
            _ = mem.write(u + 7 + i, u8, @as(u8, @intCast(hp)));
        }

        const jdge = r.DerefEntity(.Jdge, 0, 0);
        rf.TriggerLoad_InRace(jdge, rc.MAGIC_RSTR);
        close();
    }

    // TODO: repurpose to run every EventJdgeBegn, maybe add different init if
    // that introduces issues with state loop
    fn init() void {
        values.vehicle = r.ReadEntityValue(.Hang, 0, 0x73, u8);
        values.track = r.ReadEntityValue(.Hang, 0, 0x5D, u8);
        values.mirror = r.ReadEntityValue(.Hang, 0, 0x6E, u8);
        values.laps = r.ReadEntityValue(.Hang, 0, 0x8F, u8);
        values.racers = r.ReadEntityValue(.Hang, 0, 0x72, u8); // also: 0x50C558
        values.ai_speed = r.ReadEntityValue(.Hang, 0, 0x90, u8) - 1;
        //values.winnings_split = r.ReadEntityValue(.Hang, 0, 0x91, u8);
        const u: [14]u8 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x0C, 0x41 }, [14]u8);
        for (u[0..7], u[7..14], 0..) |lv, hp, i| {
            values.up_lv[i] = lv;
            values.up_hp[i] = hp;
        }

        initialized = true;
    }

    fn open() void {
        if (!gf.GameFreezeEnable(menu_key)) return;
        //rf.swrSound_PlaySound(78, 6, 0.25, 1.0, 0);
        data.idx = 0;
        menu_active = true;
    }

    fn close() void {
        if (!gf.GameFreezeDisable(menu_key)) return;
        rf.swrSound_PlaySound(77, 6, 0.25, 1.0, 0);
        _ = mem.write(rc.ADDR_PAUSE_STATE, u8, 3);
        menu_active = false;
    }

    fn update() void {
        if (gs.in_race == .JustOn)
            init();

        if (!gs.in_race.on() or !initialized) return;

        const pausestate: u8 = mem.read(rc.ADDR_PAUSE_STATE, u8);
        if (menu_active and QolState.input_pause.gets() == .JustOn) {
            close();
        } else if (pausestate == 2 and QolState.input_pause.gets() == .JustOn) {
            open();
        }

        if (menu_active) data.UpdateAndDraw();
    }
};

const QuickRaceMenuItems = [_]mi.MenuItem{
    mi.MenuItemRange(&QuickRaceMenu.values.fps, "FPS", 10, 500, true),
    mi.MenuItemSpacer(),
    mi.MenuItemList(&QuickRaceMenu.values.vehicle, "Vehicle", &rc.Vehicles, true),
    // FIXME: maybe change to menu order?
    mi.MenuItemList(&QuickRaceMenu.values.track, "Track", &rc.TracksById, true),
    mi.MenuItemSpacer(),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[0], rc.UpgradeCategories[0], &rc.UpgradeNames[0 * 6 .. 0 * 6 + 6].*, false),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[1], rc.UpgradeCategories[1], &rc.UpgradeNames[1 * 6 .. 1 * 6 + 6].*, false),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[2], rc.UpgradeCategories[2], &rc.UpgradeNames[2 * 6 .. 2 * 6 + 6].*, false),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[3], rc.UpgradeCategories[3], &rc.UpgradeNames[3 * 6 .. 3 * 6 + 6].*, false),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[4], rc.UpgradeCategories[4], &rc.UpgradeNames[4 * 6 .. 4 * 6 + 6].*, false),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[5], rc.UpgradeCategories[5], &rc.UpgradeNames[5 * 6 .. 5 * 6 + 6].*, false),
    mi.MenuItemList(&QuickRaceMenu.values.up_lv[6], rc.UpgradeCategories[6], &rc.UpgradeNames[6 * 6 .. 6 * 6 + 6].*, false),
    mi.MenuItemSpacer(),
    mi.MenuItemToggle(&QuickRaceMenu.values.mirror, "Mirror"),
    mi.MenuItemRange(&QuickRaceMenu.values.laps, "Laps", 1, 5, true),
    mi.MenuItemRange(&QuickRaceMenu.values.racers, "Racers", 1, 12, true),
    mi.MenuItemList(&QuickRaceMenu.values.ai_speed, "AI Speed", &[_][*:0]const u8{ "Slow", "Average", "Fast" }, true),
    //mi.MenuItemList(&QuickRaceMenu.values.winnings_split, "Winnings", &[_][]const u8{ "Fair", "Skilled", "Winner Takes All" }, true),
    mi.MenuItemSpacer(),
    mi.MenuItemButton("Race!", &QuickRaceConfirm),
};

fn QuickRaceCallback(m: *Menu) callconv(.C) bool {
    var result = false;
    if (m.inputs.cb) |cb| {
        // set all to NU
        if (cb[2](.JustOn)) {
            QuickRaceMenu.values.up_lv = comptime [_]i32{0} ** 7;
            result = true;
        }
        // set all to MU
        if (cb[3](.JustOn)) {
            QuickRaceMenu.values.up_lv = comptime [_]i32{5} ** 7;
            result = true;
        }
        // confirm from anywhere
        if (cb[1](.JustOn)) {
            QuickRaceMenu.load_race();
            return false;
        }
    }
    return result;
}

fn QuickRaceConfirm(m: *Menu) callconv(.C) bool {
    if (m.inputs.cb) |cb| {
        if (cb[0](.JustOn)) {
            QuickRaceMenu.load_race();
        }
    }
    return false;
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
    _ = w32wm.ShowCursor(0);
    QolHandleSettings(gf);

    QuickRaceMenu.gs = gs;
    QuickRaceMenu.gf = gf;
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // TODO: look into using in-game default setter, see fn_45BD90

    if (QolState.default_laps >= 1 and QolState.default_laps <= 5)
        r.WriteEntityValue(.Hang, 0, 0x8F, u8, @as(u8, @truncate(QolState.default_laps)));

    if (QolState.default_racers >= 1 and QolState.default_racers <= 12)
        _ = mem.write(0x50C558, u8, @as(u8, @truncate(QolState.default_racers))); // racers
}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    QuickRaceMenu.close();
}

// HOOKS

export fn OnSettingsLoad(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    QolHandleSettings(gf);
}

export fn InputUpdateB(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    QolUpdateInput(gf);
    QuickRaceMenu.update_input();
}

export fn InputUpdateKeyboardA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // map xinput start to esc
    const start_on: u32 = @intFromBool(QolState.input_pause.gets() == .On);
    const start_just_on: u32 = @intFromBool(QolState.input_pause.gets() == .JustOn);
    _ = mem.write(rc.INPUT_RAW_STATE_ON + 4, u32, start_on);
    _ = mem.write(rc.INPUT_RAW_STATE_JUST_ON + 4, u32, start_just_on);
}

export fn TimerUpdateB(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // TODO: move to global state, see also qll_savestate->EarlyEngineUpdateStage20A
    // only not nullptr if in race scene
    const player_ok: bool = mem.read(rc.RACE_DATA_PLAYER_RACE_DATA_PTR_ADDR, u32) != 0 and
        r.ReadRaceDataValue(0x84, u32) != 0;
    const gui_on: bool = mem.read(rc.ADDR_GUI_STOPPED, u32) == 0;
    if (player_ok and gui_on and QolState.fps_limiter)
        QuickRaceMenu.FpsTimer.Sleep();
}

// FIXME: settings toggles for both of these
// FIXME: probably want this mid-engine update, immediately before Jdge gets processed?
export fn EarlyEngineUpdateB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // Quick Restart
    if (gs.in_race.on() and
        QolState.input_quickstart.gets() == .On and
        QolState.input_pause.gets() == .JustOn and
        QolState.quickstart)
    {
        const jdge = r.DerefEntity(.Jdge, 0, 0);
        rf.swrSound_PlaySound(77, 6, 0.25, 1.0, 0);
        rf.TriggerLoad_InRace(jdge, rc.MAGIC_RSTR);
    }

    // Quick Race Menu
    if (QolState.quickrace)
        QuickRaceMenu.update();
}

export fn TextRenderB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    if (gs.in_race.on()) {
        if (gs.in_race == .JustOn) race.reset();

        const race_times: [6]f32 = r.ReadRaceDataValue(0x60, [6]f32);
        const total_time: f32 = race_times[5];

        //if (gs.player.in_race_count.on()) {}

        if (!gs.player.in_race_count.on()) {
            if (gs.player.dead == .JustOn) race.total_deaths += 1;

            if (gs.player.boosting == .JustOn) race.set_last_boost_start(total_time);
            if (gs.player.boosting.on()) race.set_total_boost(total_time);
            if (gs.player.boosting == .JustOff) race.set_total_boost(total_time);

            if (gs.player.underheating == .JustOn) race.set_last_underheat_start(total_time);
            if (gs.player.underheating.on()) race.set_total_underheat(total_time);
            if (gs.player.underheating == .JustOff) race.set_total_underheat(total_time);

            if (gs.player.overheating == .JustOn) race.set_last_overheat_start(total_time);
            if (gs.player.overheating.on()) race.set_total_overheat(total_time);
            if (gs.player.overheating == .JustOff) race.set_total_overheat(total_time);
            if (gs.player.overheating == .JustOff) race.set_fire_finish_duration(total_time);
        }

        const show_stats: bool = r.ReadEntityValue(.Jdge, 0, 0x08, u32) & 0x0F == 2;
        if (gs.player.in_race_results.on() and show_stats) {
            const upg_postfix = if (gs.player.upgrades) "" else "  NU";
            RenderRaceResultHeader(0, "{d:>2.0}/{s}{s}", .{
                gs.fps_avg,
                rc.UpgradeNames[gs.player.upgrades_lv[0]],
                upg_postfix,
            });

            for (0..7) |i| RenderRaceResultStatUpgrade(
                2 + @as(u8, @truncate(i)),
                @as(u8, @truncate(i)),
                gs.player.upgrades_lv[i],
                gs.player.upgrades_hp[i],
            );

            RenderRaceResultStatU(10, "Deaths", race.total_deaths);
            RenderRaceResultStatTime(11, "Boost Time", race.total_boost_duration);
            RenderRaceResultStatF(12, "Boost Ratio", race.total_boost_ratio);
            RenderRaceResultStatTime(13, "First Boost", race.first_boost_time);
            RenderRaceResultStatTime(14, "Underheat Time", race.total_underheat);
            RenderRaceResultStatTime(15, "Fire Finish", race.fire_finish_duration);
            RenderRaceResultStatTime(16, "Overheat Time", race.total_overheat);
        }
    }
}
