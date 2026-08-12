const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const w32 = @import("zigwin32");
const ShowCursor = w32.ui.windows_and_messaging.ShowCursor;
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;
const XINPUT_GAMEPAD_BUTTON_INDEX = @import("core/Input.zig").XINPUT_GAMEPAD_BUTTON_INDEX;

const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;

const debug = @import("core/Debug.zig");

const timing = @import("util/timing.zig");
const spatial = @import("util/spatial.zig");
const m = @import("util/menu.zig");
const Menu = m.Menu;
const MenuItem = m.MenuItem;
const InputGetFnType = @import("util/menu.zig").InputGetFnType;
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");
const st = @import("util/active_state.zig");
const bmem = @import("util/base/base_memory.zig");

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
const rs = @import("racer").Save;

const InputMap = @import("core/Input.zig").InputMap;
const ButtonInputMap = @import("core/Input.zig").ButtonInputMap;
const AxisInputMap = @import("core/Input.zig").AxisInputMap;
const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;
const Setting = @import("core/ASettings.zig").ASettingSent;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// - fix: remove double mouse cursor
// - fix: pause game with xinput controller (maps Start -> Esc)
// - fix: toggle Jinn Reeso with cheat, instead of only enabling
// - fix: toggle Cy Yunga with cheat, instead of only enabling
// - fix: bugfix Cy Yunga cheat having no audio
// - fix: bugfix map rendering not accounting for hi-res flag
// - fix: bugfix changing camera with F1-F4 keys not persisting after a crash
// - fix: remove 1px gap on right and bottom of viewport when rendering sprites
//     - this may cut off sprites placed right at the edge, depending on your resolution settings
// - feat: quick restart
//     - CONTROLS:          Tab+Esc          Back+Start
// - feat: quick race menu
//     - create a new race from inside a race
//     - select pod, track, upgrade stack and other race settings
//     - CONTROLS:                          keyboard    xinput
//       Open                               Esc         Start       Hold or double-tap while unpaused
//       Close                              Esc         B
//       Navigate                           ↑↓          D-Up, D-Dn
//       Scroll item options                ←→          D-Lf, D-Rt
//       Tab-scroll item options            Home, End   LB, RB
//       Interact*                          Enter       A           Special behaviour depending on menu item
//       Quick Confirm                      Space       Start       "Race!" immediately from any menu item
//       All Upgrades MIN                   TAB-LEFT                While selecting any upgrade
//       All Upgrades MAX                   TAB-RIGHT               While selecting any upgrade
//       Apply FPS immediately              INTERACT                While selecting FPS (Practice Mode only)
//       Scroll FPS preset                  TAB-SCROLL              While selecting FPS
//       Swap track order                   INTERACT                While selecting TRACK
//       Scroll track by planet             TAB-SCROLL              While selecting TRACK in PLANET order
//       Scroll track by circuit            TAB-SCROLL              While selecting TRACK in CIRCUIT order
//       Toggle vehicle as favorite         INTERACT                While selecting VEHICLE
//       Scroll favorite vehicle            TAB-SCROLL              While selecting VEHICLE
// - feat: post-race stats readout
//     - tfps
//     - full upgrade stack with healths
//     - death count
//     - total boost duration
//     - boost ratio
//     - first boost timestamp
//     - underheat duration
//     - fire finish duration
//     - overheat duration
// - feat: show true values of times on post-race screen, via the underlying hexadecimal number
// - feat: show milliseconds on all timers
// - feat: limit fps during races (configurable via quick race menu)
// - feat: n64 pitch input toggle (experimental) (accessible via quick race menu)
// - feat: skip planet cutscene
// - feat: skip podium cutscene
// - feat: custom default number of racers
// - feat: custom default number of laps
// - feat: custom default race camera, with option to auto-update
// - feat: fast countdown timer
// - feat: run game in background
// - feat: patch truguts cheat to give more truguts and have infinite uses
// - feat: auto-reset on missed starting boost, underheat, engine fire and death
// - feat: track select remembers selection when leaving menu and between sessions
// - feat: fast menu navigation
// - feat: allow dpad input for menu navigation
// - feat: clear best times with hotkey on track detail screen
//     - CONTROLS:                  keyboard
//       Clear Best Lap             1+Backspace
//       Clear 3-Lap Record         3+Backspace
// - SETTINGS:
//   quick_restart_enable           bool
//   quick_race_menu_enable         bool
//   ms_timer_enable                bool
//   ms_timer_hud_enable            bool
//   ms_timer_finish_enable         bool
//   fps_limiter_enable             bool
//   default_racers                 u32     max 12
//   default_laps                   u32     max 5
//   default_camera                 u32     1,2,4,5
//   default_camera_auto            bool
//   fast_countdown_enable          bool
//   fast_countdown_duration        f32     min 0.05, max 3.00
//   fix_viewport_edges             bool
//   run_in_background              bool
//   autoreset_enable               bool
//   autoreset_dead_enable          bool
//   autoreset_dead_delay           f32     default 0.50
//   autoreset_fire_enable          bool
//   autoreset_fire_delay           f32     default 3.00, time limit per engine fire
//   autoreset_firstboost_enable    bool
//   autoreset_firstboost_delay     f32     default 0.25, time limit from when the first boost is ready
//   autoreset_underheat_enable     bool
//   autoreset_underheat_delay      f32     default 3.00, time limit per underheat
//   trackselect_remember           bool
//   trackselect_last               u32     0..24
//   fast_navigation                bool
//   dpad_navigation                bool
//   show_postrace_times_hex        bool
//   clear_records_enable           bool
//   favorite_characters            u32     bitfield where character id = nth bit
//   menu_track_order               str     "PLANET" or "CIRCUIT"

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
    var h_s_default_camera: ?SettingHandle = null;
    var h_s_default_camera_auto: ?SettingHandle = null;
    var h_s_ms_timer: ?SettingHandle = null;
    var h_s_ms_timer_hud: ?SettingHandle = null;
    var h_s_ms_timer_finish: ?SettingHandle = null;
    var h_s_fps_limiter: ?SettingHandle = null;
    var h_s_skip_planet_cutscenes: ?SettingHandle = null;
    var h_s_skip_podium_cutscene: ?SettingHandle = null;
    var h_s_fix_viewport_edges: ?SettingHandle = null;
    var h_s_run_in_background: ?SettingHandle = null;
    var h_s_autoreset_enable: ?SettingHandle = null;
    var h_s_autoreset_dead_enable: ?SettingHandle = null;
    var h_s_autoreset_dead_delay: ?SettingHandle = null;
    var h_s_autoreset_fire_enable: ?SettingHandle = null;
    var h_s_autoreset_fire_delay: ?SettingHandle = null;
    var h_s_autoreset_firstboost_enable: ?SettingHandle = null;
    var h_s_autoreset_firstboost_delay: ?SettingHandle = null;
    var h_s_autoreset_underheat_enable: ?SettingHandle = null;
    var h_s_autoreset_underheat_delay: ?SettingHandle = null;
    var h_s_trackselect_remember: ?SettingHandle = null;
    var h_s_trackselect_last: ?SettingHandle = null;
    var h_s_fast_navigation: ?SettingHandle = null;
    var h_s_dpad_navigation: ?SettingHandle = null;
    var h_s_show_postrace_times_hex: ?SettingHandle = null;
    var h_s_clear_records_enable: ?SettingHandle = null;
    var s_quickstart: bool = false;
    var s_quickrace: bool = false;
    var s_default_racers: u32 = 12;
    var s_default_laps: u32 = 3;
    var s_default_camera: u32 = 3;
    var s_default_camera_auto: bool = false;
    var s_ms_timer: bool = false;
    var s_ms_timer_hud: bool = false;
    var s_ms_timer_finish: bool = false;
    var s_fps_limiter: bool = false;
    var s_skip_planet_cutscenes: bool = false;
    var s_skip_podium_cutscene: bool = false;
    var s_fix_viewport_edges: bool = false;
    var s_run_in_background: bool = false;
    var s_autoreset_enable: bool = false;
    var s_autoreset_dead_enable: bool = false;
    var s_autoreset_dead_delay: f32 = 0.5;
    var s_autoreset_fire_enable: bool = false;
    var s_autoreset_fire_delay: f32 = 3.0;
    var s_autoreset_firstboost_enable: bool = false;
    var s_autoreset_firstboost_delay: f32 = 0.25;
    var s_autoreset_underheat_enable: bool = false;
    var s_autoreset_underheat_delay: f32 = 3.0;
    var s_trackselect_remember: bool = false;
    var s_trackselect_last: u32 = 0;
    var s_fast_navigation: bool = false;
    var s_dpad_navigation: bool = false;
    var s_show_postrace_times_hex: bool = false;
    var s_clear_records_enable: bool = false;

    var input_pause_data = ButtonInputMap{ .kb = .ESCAPE, .xi = .START };
    var input_unpause_data = ButtonInputMap{ .kb = .ESCAPE, .xi = .B };
    var input_quickstart_data = ButtonInputMap{ .kb = .TAB, .xi = .BACK };
    var input_pause = input_pause_data.inputMap();
    var input_unpause = input_unpause_data.inputMap();
    var input_quickstart = input_quickstart_data.inputMap();

    var fcam_buf: [32]u8 = undefined;
    var cam_prev: u32 = 0xFFFFFFFF;
    var cam_cman: ?*re.cMan.cMan = null;

    var autoreset_dead: st.ActiveState = .Off;
    var autoreset_dead_timer: f32 = 0;
    var autoreset_fire_timer: f32 = 0;
    var autoreset_has_boost_charged: bool = false;
    var autoreset_firstboost_timer: f32 = 0;
    var autoreset_has_boost_boosted: bool = false;
    var autoreset_underheat_timer: f32 = 0;

    fn UpdateInput(gf: *GlobalFn) callconv(.C) void {
        input_pause.update(gf);
        input_unpause.update(gf);
        input_quickstart.update(gf);
    }

    fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "qol", settingsUpdate);
        h_s_section = section;

        h_s_quickstart =
            gf.ASettingOccupy(section, "quick_restart_enable", .B, .{ .b = false }, &s_quickstart, null);
        h_s_quickrace =
            gf.ASettingOccupy(section, "quick_race_menu_enable", .B, .{ .b = false }, &s_quickrace, null);
        h_s_default_racers =
            gf.ASettingOccupy(section, "default_racers", .U, .{ .u = 12 }, null, settingsUpdateRacers);
        h_s_default_laps =
            gf.ASettingOccupy(section, "default_laps", .U, .{ .u = 3 }, null, settingsUpdateLaps);
        h_s_default_camera =
            gf.ASettingOccupy(section, "default_camera", .U, .{ .u = 1 }, null, settingsUpdateCamera);
        h_s_default_camera_auto =
            gf.ASettingOccupy(section, "default_camera_auto", .B, .{ .b = false }, &s_default_camera_auto, null);
        h_s_ms_timer =
            gf.ASettingOccupy(section, "ms_timer_enable", .B, .{ .b = false }, &s_ms_timer, null);
        h_s_ms_timer_hud =
            gf.ASettingOccupy(section, "ms_timer_hud_enable", .B, .{ .b = false }, &s_ms_timer_hud, null);
        h_s_ms_timer_finish =
            gf.ASettingOccupy(section, "ms_timer_finish_enable", .B, .{ .b = false }, &s_ms_timer_finish, null);
        h_s_fps_limiter =
            gf.ASettingOccupy(section, "fps_limiter_enable", .B, .{ .b = false }, &s_fps_limiter, null);
        h_s_skip_planet_cutscenes =
            gf.ASettingOccupy(section, "skip_planet_cutscenes", .B, .{ .b = false }, &s_skip_planet_cutscenes, null);
        h_s_skip_podium_cutscene =
            gf.ASettingOccupy(section, "skip_podium_cutscene", .B, .{ .b = false }, &s_skip_podium_cutscene, null);
        h_s_fix_viewport_edges =
            gf.ASettingOccupy(section, "fix_viewport_edges", .B, .{ .b = false }, &s_fix_viewport_edges, null);
        h_s_run_in_background =
            gf.ASettingOccupy(section, "run_in_background", .B, .{ .b = false }, &s_run_in_background, null);

        h_s_autoreset_enable =
            gf.ASettingOccupy(section, "autoreset_enable", .B, .{ .b = false }, &s_autoreset_enable, null);
        h_s_autoreset_dead_enable =
            gf.ASettingOccupy(section, "autoreset_dead_enable", .B, .{ .b = false }, &s_autoreset_dead_enable, null);
        h_s_autoreset_dead_delay =
            gf.ASettingOccupy(section, "autoreset_dead_delay", .F, .{ .f = 0.5 }, &s_autoreset_dead_delay, null);
        h_s_autoreset_fire_enable =
            gf.ASettingOccupy(section, "autoreset_fire_enable", .B, .{ .b = false }, &s_autoreset_fire_enable, null);
        h_s_autoreset_fire_delay =
            gf.ASettingOccupy(section, "autoreset_fire_delay", .F, .{ .f = 3.0 }, &s_autoreset_fire_delay, null);
        h_s_autoreset_firstboost_enable =
            gf.ASettingOccupy(section, "autoreset_firstboost_enable", .B, .{ .b = false }, &s_autoreset_firstboost_enable, null);
        h_s_autoreset_firstboost_delay =
            gf.ASettingOccupy(section, "autoreset_firstboost_delay", .F, .{ .f = 0.25 }, &s_autoreset_firstboost_delay, null);
        h_s_autoreset_underheat_enable =
            gf.ASettingOccupy(section, "autoreset_underheat_enable", .B, .{ .b = false }, &s_autoreset_underheat_enable, null);
        h_s_autoreset_underheat_delay =
            gf.ASettingOccupy(section, "autoreset_underheat_delay", .F, .{ .f = 3.0 }, &s_autoreset_underheat_delay, null);

        h_s_trackselect_remember =
            gf.ASettingOccupy(section, "trackselect_remember", .B, .{ .b = false }, &s_trackselect_remember, null);
        h_s_trackselect_last =
            gf.ASettingOccupy(section, "trackselect_last", .U, .{ .u = 0 }, null, null);
        h_s_fast_navigation =
            gf.ASettingOccupy(section, "fast_navigation", .B, .{ .b = false }, &s_fast_navigation, null);
        h_s_dpad_navigation =
            gf.ASettingOccupy(section, "dpad_navigation", .B, .{ .b = false }, &s_dpad_navigation, null);

        h_s_show_postrace_times_hex =
            gf.ASettingOccupy(section, "show_postrace_times_hex", .B, .{ .b = false }, &s_show_postrace_times_hex, null);
        h_s_clear_records_enable =
            gf.ASettingOccupy(section, "clear_records_enable", .B, .{ .b = false }, &s_clear_records_enable, null);

        FastCountdown.h_s_enable =
            gf.ASettingOccupy(section, "fast_countdown_enable", .B, .{ .b = false }, &FastCountdown.s_enable, null);
        FastCountdown.h_s_duration =
            gf.ASettingOccupy(section, "fast_countdown_duration", .F, .{ .f = 1.0 }, &FastCountdown.s_duration, null);

        // FIXME: figure out how to init without this; probably need later zig
        //  version. also, is this even necessary if ASettingOccupy writes it?
        _ = std.fmt.bufPrintZ(&QuickRaceMenu.s_menu_track_order, "PLANET", .{}) catch unreachable;
        QuickRaceMenu.h_s_fps_default =
            gf.ASettingOccupy(section, "fps_limiter_default", .U, .{ .u = 24 }, &QuickRaceMenu.s_fps_default, null);
        QuickRaceMenu.h_s_favorite_vehicles =
            gf.ASettingOccupy(section, "favorite_vehicles", .U, .{ .u = 0 }, &QuickRaceMenu.s_favorite_vehicles, null);
        QuickRaceMenu.h_s_menu_track_order =
            gf.ASettingOccupy(section, "menu_track_order", .Str, .{ .str = "PLANET" }, &QuickRaceMenu.s_menu_track_order, null);
    }

    // TODO: setting to control whether default racers automatically updates
    fn settingsUpdateRacers(new_value: Setting.Value) callconv(.C) void {
        s_default_racers = std.math.clamp(new_value.u, 1, 12);
        if (h_s_default_racers) |h| QuickRaceMenu.gf.ASettingUpdate(h, .{ .u = s_default_racers });

        QuickRaceMenu.values.racers = @intCast(s_default_racers);
        if (QuickRaceMenu.gf.SInitLatePassed()) {
            _ = mem.write(0x50C558, i8, @as(i8, @intCast(s_default_racers)));
            re.Manager.entity(.Hang, 0).Racers = @intCast(s_default_racers);
        }
    }

    // TODO: setting to control whether default laps automatically updates
    fn settingsUpdateLaps(new_value: Setting.Value) callconv(.C) void {
        s_default_laps = std.math.clamp(new_value.u, 1, 5);
        if (h_s_default_laps) |h| QuickRaceMenu.gf.ASettingUpdate(h, .{ .u = s_default_laps });

        QuickRaceMenu.values.laps = @intCast(s_default_laps);
        if (QuickRaceMenu.gf.SInitLatePassed()) {
            re.Manager.entity(.Hang, 0).Laps = @intCast(s_default_laps);
        }
    }

    fn settingsUpdateCamera(new_value: Setting.Value) callconv(.C) void {
        s_default_camera = std.math.clamp(new_value.u, 1, 5);
        if (s_default_camera == 3) s_default_camera = 1;
        if (h_s_default_camera) |h| QuickRaceMenu.gf.ASettingUpdate(h, .{ .u = s_default_camera });

        // patch CMan_SetNewCamera_451D60 call at end of CMan_HandlePreRaceSweepCam_451EF0
        _ = mem.write(0x4525AE, u8, @as(u8, @intCast(s_default_camera)));
    }

    fn settingsUpdate(changed: [*]Setting, len: usize) callconv(.C) void {
        var update_fast_countdown: bool = false;

        for (changed[0..len]) |*setting| {
            const name = std.mem.span(setting.name);

            if (std.mem.eql(u8, "quick_race_menu_enable", name)) {
                if (!s_quickrace) QuickRaceMenu.close();
                continue;
            }

            if (std.mem.eql(u8, "ms_timer_enable", name)) {
                PatchRaceTimerMsHud(s_ms_timer and s_ms_timer_hud);
                PatchRaceTimerMsFinish(s_ms_timer and s_ms_timer_finish);
                continue;
            }
            if (std.mem.eql(u8, "ms_timer_hud_enable", name)) {
                PatchRaceTimerMsHud(s_ms_timer and s_ms_timer_hud);
                continue;
            }
            if (std.mem.eql(u8, "ms_timer_finish_enable", name)) {
                PatchRaceTimerMsFinish(s_ms_timer and s_ms_timer_finish);
                continue;
            }
            if (std.mem.eql(u8, "skip_planet_cutscenes", name)) {
                PatchPlanetCutscenes(s_skip_planet_cutscenes);
                continue;
            }
            if (std.mem.eql(u8, "skip_podium_cutscene", name)) {
                PatchPodiumCutscene(s_skip_podium_cutscene);
                continue;
            }
            if (std.mem.eql(u8, "fix_viewport_edges", name)) {
                PatchViewportEdges(s_fix_viewport_edges);
                continue;
            }
            if (std.mem.eql(u8, "run_in_background", name)) {
                PatchWindowBackgroundActivity(s_run_in_background);
                continue;
            }
            if (std.mem.eql(u8, "trackselect_remember", name)) {
                PatchTrackSelectEntry(s_trackselect_remember);
                continue;
            }
            if (std.mem.eql(u8, "trackselect_last", name)) {
                s_trackselect_last = if (setting.value.u > 24) 0 else setting.value.u;
                continue;
            }
            if (std.mem.eql(u8, "fast_navigation", name)) {
                PatchMenuNavigationSpeed(s_fast_navigation);
                continue;
            }

            if (std.mem.eql(u8, "fps_limiter_default", name)) {
                QuickRaceMenu.FpsTimer.SetPeriod(QuickRaceMenu.s_fps_default);
                QuickRaceMenu.values.fps = @intCast(QuickRaceMenu.s_fps_default);
                continue;
            }
            if (std.mem.eql(u8, "menu_track_order", name)) {
                var buf: [64]u8 = undefined;
                const s = std.ascii.upperString(&buf, std.mem.span(@as([*:0]const u8, &QuickRaceMenu.s_menu_track_order)));
                const use_circuit_order = std.mem.eql(u8, "CIRCUIT", s);
                QuickRaceMenu.set_track_order(use_circuit_order);
                continue;
            }

            if (std.mem.eql(u8, "fast_countdown_enable", name) or
                std.mem.eql(u8, "fast_countdown_duration", name))
            {
                update_fast_countdown = true;
                continue;
            }
        }

        if (update_fast_countdown) {
            if (FastCountdown.s_enable) FastCountdown.init(FastCountdown.s_duration);
            FastCountdown.patch(FastCountdown.s_enable);
        }
    }
};

// F-KEY CAMERA GLITCH

const fcam_src_asm = [7]u8{
    0x8B, 0x4C, 0x24, 0x08, // mov ecx, [esp+08]
    0x89, 0x48, 0x7C, // mov [eax+7C], ecx
};

// TODO: convert hand-rolled asm to x86.zig fns
// adds CMan.CamModeOnRespawn=NewCamMode to fn_451D60, which is called by all ccf* paths
fn PatchCameraFKeys(enable: bool) void {
    if (enable) {
        var d: x86.Detour = undefined;
        d.Start(0x451D64, 0x451D6B, &QolState.fcam_buf);
        d.addr = mem.write_bytes(d.addr, &fcam_src_asm);
        d.addr = mem.write_bytes(d.addr, &[6]u8{ 0x89, 0x88, 0x80, 0x00, 0x00, 0x00 }); // mov [eax+80], ecx
        d.End();
    } else {
        _ = mem.write_bytes(0x451D64, &fcam_src_asm);
    }
}

// HUD TIMER MS

fn PatchRaceTimerMsHud(enable: bool) void {
    const draw_fn = if (enable) rt.fnDrawTime3 else rt.fnDrawTime2;
    // hudDrawRaceHud
    _ = x86.call(0x460BD3, @intFromPtr(draw_fn));
    _ = x86.call(0x460E6B, @intFromPtr(draw_fn));
    _ = x86.call(0x460ED9, @intFromPtr(draw_fn));
}

fn PatchRaceTimerMsFinish(enable: bool) void {
    const draw_fn = if (enable) rt.fnDrawTime3 else rt.fnDrawTime2;
    // hudDrawRaceResults
    const end_race_timer_offset: u8 = if (enable) 8 else 0;
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
    if (enable) {
        _ = x86.nop_until(0x43D48C, 0x43D48C + 2);
        _ = x86.nop_until(0x43D495, 0x43D495 + 2);
        _ = x86.nop_until(0x43D49E, 0x43D49E + 2);
        _ = x86.nop_until(0x43D4B4, 0x43D4B4 + 2);
    } else {
        _ = x86.JNZ(0x43D48C, 0x43D48C + 0x09 + 2);
        _ = x86.JZ(0x43D495, 0x43D495 + 0x29 + 2);
        _ = x86.JLE(0x43D49E, 0x43D49E + 0x20 + 2);
        _ = x86.JZ(0x43D4B4, 0x43D4B4 + 0x0A + 2);
    }
}

// TODO: verify this is the only difference between PC and N64/DC
// NOTE: the actual difference in terms of pitch scaling is that N64/DC simply
//  doesn't scale pitch at all. this way was chosen because it makes the patch
//  simpler and should be equivalent, but a more "pure" patch might just bypass
//  the scaling routine altogether
/// experimental patch enabling the greater pitch input range used by N64
fn PatchN64Pitch(enable: bool) void {
    if (enable) {
        _ = mem.write(@intFromPtr(ri.PITCH_SCALE_MAX), f32, 1.0);
        _ = mem.write(@intFromPtr(ri.PITCH_SCALE_MIN), f32, -1.0);
    } else {
        _ = mem.write(@intFromPtr(ri.PITCH_SCALE_MAX), u32, 0x3F4CCCCD); // +0.8
        _ = mem.write(@intFromPtr(ri.PITCH_SCALE_MIN), u32, 0xBF4CCCCD); // -0.8
    }
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

// WINDOW

const window_activity_asm = [_]u8{ 0x8B, 0x74, 0x24, 0x0C, 0x85, 0xF6, 0x74, 0x6A };

// TODO: get keyboard input to work when unfocused; presumably because window messages not being passed
// force Window_SetActive__423AE0 to always set window as active
fn PatchWindowBackgroundActivity(enable: bool) void {
    var offset: usize = 0x423AE1;
    if (enable) {
        offset = x86.mov_esi_imm32(offset, u32, 1);
        offset = x86.nop_until(offset, 0x423AE1 + window_activity_asm.len);
    } else {
        offset = mem.write_bytes(offset, &window_activity_asm);
    }
    std.debug.assert(offset == 0x423AE9);
}

// GAME CHEATS

// TODO: add quick toggle to menus
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

// infinite uses and greater amount
fn PatchTrugutsCheat(enable: bool) void {
    const amount_addr: u32 = 0x410700 + 6;
    const uses_addr: u32 = 0x410F8C;
    if (enable) {
        _ = mem.write(amount_addr, u32, 10000);
        var off: u32 = uses_addr;
        off = x86.jmp_rel(off, 0x410FB4); // skip limit check
        off = x86.nop_until(off, 0x410F90);
    } else {
        _ = mem.write(amount_addr, u32, 1000);
        _ = mem.write_bytes(uses_addr, &[4]u8{ 0x8B, 0x44, 0x24, 0x10 }); // mov eax, [esp+0x10]
    }
}

// REMEMBERING TRACK SELECTION

// in fn_43B240 Hang_DrawTrackSelect
fn PatchTrackSelectEntry(enable: bool) void {
    // - 0043B29A -> 88 5E 5E (mov [esi+5E], bl; pHang->Circuit = 0)
    //   could start as early as 43B28D and include if statement in nop'ing
    const off1: u32 = 0x43B29A;
    const end1: u32 = off1 + 3;

    // - 0043B2BE -> 89 1D D0 95 E2 00 (mov [MenuPosX], ebx; MenuPosX = 0)
    const off2: u32 = 0x43B2BE;
    const end2: u32 = off2 + 6;

    if (enable) {
        _ = x86.nop_until(off1, end1);
        var o = x86.call(off2, @intFromPtr(&CallbackTrackSelectEntry));
        _ = x86.nop_until(o, end2);
    } else {
        _ = mem.write_bytes(off1, &[3]u8{ 0x88, 0x5E, 0x5E }); // mov r/m8, r8
        _ = mem.write_bytes(off2, &[6]u8{ 0x89, 0x1D, 0xD0, 0x95, 0xE2, 0x00 }); // mov r/m32, r32
    }
}

fn CallbackTrackSelectEntry() callconv(.C) void {
    const p_menu_pos_x: *i32 = @ptrFromInt(0xE295D0);

    const hang = re.Manager.entity(.Hang, 0);
    p_menu_pos_x.* = rtr.TrackCircuitNthTrackMap[hang.Track];
}

// FAST MENU NAVIGATION

var nav_asm: [96]u8 = undefined;

fn PatchMenuNavigationSpeed(enable: bool) void {
    var off: u32 = 0;

    // TODO: pause menu: inputs ignored while scrolling in

    // pod select: select/cancel input ignored while scrolling
    if (enable) {
        _ = x86.nop_until(0x435E23, 0x435E23 + 2); // skip scroll timer check (cancel)
        _ = x86.nop_until(0x435E43, 0x435E43 + 2); // skip scroll timer check (select)
    } else {
        _ = x86.JNZ(0x435E23, 0x435E32);
        _ = x86.JNZ(0x435E43, 0x435E62);
    }

    // pod select: wait time before advancing after selecting pod
    if (enable) {
        // skip through special state that makes you wait before transitioning
        off = mem.write_bytes(0x435B6D, &[10]u8{ //mov [E295A0], 00000000 (MenuTimer1=0.0)
            0xC7, 0x05, 0xA0, 0x95, 0xE2, 0x00,
            0x00, 0x00, 0x00, 0x00,
        }); // set timer to how it would be at the end of running normally
        off = x86.nop_until(off, 0x435B87); // skip everything until part where state is changed
    } else {
        _ = mem.write_bytes(0x435B6D, &[26]u8{ // original logic decrementing and checking timer
            0x68, 0x33, 0x33, 0x53, 0xC0, 0xE8, 0x19, 0x40, 0x03, 0x00, 0xD8, 0x1D,
            0x78, 0xC7, 0x4A, 0x00, 0x83, 0xC4, 0x04, 0xDF, 0xE0, 0xF6, 0xC4, 0x40,
            0x74, 0x0A,
        });
    }

    // track select: circuit change up/down scroll lag
    if (enable) {
        _ = x86.nop_until(0x43B6F4, 0x43B6F4 + 2); // skip waiting for circuit to transition
    } else {
        _ = x86.JNZ(0x43B6F4, 0x43B766);
    }

    // track detail: input ignored during transition into
    if (enable) {
        _ = x86.nop_until(0x43B8E6, 0x43B8E6 + 2); // skip wait time
    } else {
        _ = x86.JNZ(0x43B8E6, 0x43B8F2);
    }

    // inspect vehicle: camera angle change speed (input lockout)
    // TODO: fix animation snapping on repetitive inputs
    // TODO: reimpl hold+timeout (original behaviour) in addition to fast manual scrolling
    if (enable) {
        _ = mem.write(0x43921E + 2, u32, @intFromPtr(ri.MENU_JUST_ON)); // input raw -> JustOn check (left)
        _ = mem.write(0x4392E4 + 2, u32, @intFromPtr(ri.MENU_JUST_ON)); // input raw -> JustOn check (right)
        _ = x86.nop_until(0x439233, 0x439233 + 6); // camera is animating check (left)
        _ = x86.nop_until(0x4392F9, 0x4392F9 + 6); // camera is animating check (right)
    } else {
        _ = mem.write(0x43921E + 2, u32, @intFromPtr(ri.MENU_RAW)); // test byte ptr [50C908], 0x10
        _ = mem.write(0x4392E4 + 2, u32, @intFromPtr(ri.MENU_RAW)); // test byte ptr [50C908], 0x20
        _ = x86.JZ(0x439233, 0x4392E4);
        _ = x86.JZ(0x4392F9, 0x4393A2);
    }

    // junkyard: item change speed (input lockout)
    // TODO: convert asm reroute into x86 macro function
    // TODO: reimpl hold+timeout (original behaviour) in addition to fast manual scrolling
    if (enable) {
        var d: x86.Detour = undefined;
        _ = mem.write(0x43AE9D + 1, u32, @intFromPtr(ri.MENU_JUST_ON)); // input raw -> JustOn check
        _ = x86.nop_until(0x43AF93, 0x43AF93 + 2); // camera is animating check
        d.Start(0x43AFAE, 0x43AFB9, nav_asm[0..48]);
        d.addr = x86.CMP(d.addr, .cx, null, .imm, 1);
        d.addr = x86.JZ(d.addr, 0x43AFB9);
        d.addr = x86.CMP(d.addr, .cx, null, .imm, 5);
        d.addr = x86.JZ(d.addr, 0x43AFB9);
        d.addr = x86.CMP(d.addr, .cx, null, .di, null);
        d.addr = x86.JNZ(d.addr, 0x43AFBE);
        d.End();
        d.Start(0x43AFCB, 0x43AFD6, nav_asm[48..96]);
        d.addr = x86.CMP(d.addr, .cx, null, .imm, 1);
        d.addr = x86.JZ(d.addr, 0x43AFD6);
        d.addr = x86.CMP(d.addr, .cx, null, .imm, 5);
        d.addr = x86.JZ(d.addr, 0x43AFD6);
        d.addr = x86.CMP(d.addr, .cx, null, .di, null);
        d.addr = x86.JNZ(d.addr, 0x43AFDA);
        d.End();
    } else {
        _ = mem.write(0x43AE9D + 1, u32, @intFromPtr(ri.MENU_RAW)); // mov ebp, 50C908
        _ = x86.JNZ(0x43AF93, 0x43AFE0);
        _ = mem.write_bytes(0x43AFAE, &[11]u8{ // camera anim state checks (left scroll)
            0x66, 0x83, 0xF9, 0x05, 0x74, 0x05,
            0x66, 0x3B, 0xCF, 0x75, 0x05,
        });
        _ = mem.write_bytes(0x43AFCB, &[11]u8{ // camera anim state checks (right scroll)
            0x66, 0x83, 0xF9, 0x05, 0x74, 0x05,
            0x66, 0x3B, 0xCF, 0x75, 0x04,
        });
    }

    // general: horizontal hold scroll speed (pod, track, watto shop)
    if (enable) {
        _ = mem.write(0x469D46 + 6, f32, 0.24); // hold initial delay (left)
        _ = mem.write(0x469CBC + 6, f32, 0.24); // hold initial delay (right)
        _ = mem.write(0x4AD588, f32, 0.04); // hold fast delay (both)
    } else {
        _ = mem.write(0x469D46 + 6, f32, 0.6); // dflt 0.6 3F19999A
        _ = mem.write(0x469CBC + 6, f32, 0.6); // dflt 0.6 3F19999A
        _ = mem.write(0x4AD588, f32, 0.1); // dflt 0.1 3DCCCCCD
    }

    // general: cutscene speed (affects several camera transitions)
    PatchMenuNavigationSpeedTransitions(enable);
}

// TODO: patch other 'transition' functions at end of hang cb14, only
// first one patched here
fn PatchMenuNavigationSpeedTransitions(enable: bool) void {
    var actually_enable: bool = enable;
    if (enable) blk: {
        const hang = re.Manager.entity(.Hang, 0);
        if (0 == @intFromPtr(hang)) break :blk;
        actually_enable = switch (hang.MenuScreen) {
            .Junkyard,
            .CSRival,
            .CSPodium,
            .CSNewRacer,
            .CSCantinaEntrance,
            => false,
            else => true,
        };
    }

    if (actually_enable) {
        // increase last arg of calls to Hang__45C560 in Hang_DoCameraTransition__45C3C0
        _ = mem.write(0x45C44D + 1, f32, 30.0); // push 30.0
        _ = mem.write(0x45C471 + 1, f32, 20.0); // push 20.0
    } else {
        _ = mem.write(0x45C44D + 1, f32, 1.5); // dflt 1.5 3FC00000
        _ = mem.write(0x45C471 + 1, f32, 1.0); // dflt 1.0 3F800000
    }
}

// FAST COUNTDOWN

const FastCountdown = struct {
    var h_s_enable: ?SettingHandle = null;
    var h_s_duration: ?SettingHandle = null;
    var s_enable: bool = false;
    var s_duration: f32 = 1.0;

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
        const addr: usize = if (enable) @intFromPtr(&CurrentFrametime) else @intFromPtr(rti.FRAMETIME_64);
        const prerace_max_time: u32 = if (enable) @bitCast(9.10 + CountDif) else 0x4111999A; // 9.10
        const boost_window_min: u32 = if (enable) @bitCast(0.05 * CountRatio) else 0x3D4CCCCD; // 0.05
        const boost_window_max: u32 = if (enable) @bitCast(0.30 * CountRatio) else 0x3E99999A; // 0.30
        _ = mem.write(0x45E628, usize, addr);
        _ = mem.write(0x45E2D5, u32, prerace_max_time);
        _ = mem.write(0x4AD254, u32, boost_window_min);
        _ = mem.write(0x4AD258, u32, boost_window_max);
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
        this_position = @as(*spatial.Pos3D, @ptrCast(&re.Test.pPlayer.*.?.transform.T)).*; // FIXME
    }
};

const s_head = rt.hMakeTextHeadStyle(.Default, true, null, .Center, .{rto.ToggleShadow}) catch "";

fn RenderRaceResultHeader(gf: *GlobalFn, i: i16, comptime fmt: []const u8, args: anytype) void {
    _ = gf.GDrawText(.Default, rt.hMakeText(640 - race.stat_x, race.stat_y + i * race.stat_h, fmt, args, race.stat_col, s_head) catch null);
}

const s_stat = rt.hMakeTextHeadStyle(.Default, true, null, .Right, .{rto.ToggleShadow}) catch "";

fn RenderRaceResultStat(gf: *GlobalFn, i: i16, label: [*:0]const u8, comptime value_fmt: []const u8, value_args: anytype) void {
    _ = gf.GDrawText(.Default, rt.hMakeText(640 - race.stat_x - 8, race.stat_y + i * race.stat_h, "{s}", .{label}, race.stat_col, s_stat) catch null);
    _ = gf.GDrawText(.Default, rt.hMakeText(640 - race.stat_x + 8, race.stat_y + i * race.stat_h, value_fmt, value_args, race.stat_col, null) catch null);
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

const s_upg_full = rt.hMakeTextStyle(.Green, null, .{}) catch "";
const s_upg_dmg = rt.hMakeTextStyle(.Red, null, .{}) catch "";

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

const QuickRaceMenu = extern struct {
    var h_s_fps_default: ?SettingHandle = null;
    var h_s_favorite_vehicles: ?SettingHandle = null;
    var h_s_menu_track_order: ?SettingHandle = null;
    var s_fps_default: u32 = 24;
    var s_favorite_vehicles: u32 = 0; // bitfield where vehicle id maps to nth bit
    var s_menu_track_order: [63:0]u8 = std.mem.zeroes([63:0]u8);
    var using_circuit_track_order: bool = false;

    const open_threshold: f32 = 0.75;
    var menu_active: st.ActiveState = .Off;
    var initialized: bool = false;
    // TODO: figure out if these can be removed, currently blocked by quick race menu callbacks
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
        var n64_pitch: i32 = 0;
        var n64_pitch_applied: i32 = 0;
    };

    const MenuInput = extern struct {
        kb: VIRTUAL_KEY,
        xi: XINPUT_GAMEPAD_BUTTON_INDEX,
        state: st.ActiveState = undefined,
    };

    var inputs = [_]MenuInput{
        .{ .kb = .UP, .xi = .DPAD_UP },
        .{ .kb = .DOWN, .xi = .DPAD_DOWN },
        .{ .kb = .LEFT, .xi = .DPAD_LEFT },
        .{ .kb = .RIGHT, .xi = .DPAD_RIGHT },
        .{ .kb = .RETURN, .xi = .A }, // confirm/activate
        .{ .kb = .SPACE, .xi = .START }, // quick confirm
        .{ .kb = .HOME, .xi = .LEFT_SHOULDER }, // NU
        .{ .kb = .END, .xi = .RIGHT_SHOULDER }, // MU
    };

    const InputList = [_]InputGetFnType{
        get_input(&inputs[4]),
        get_input(&inputs[5]),
        get_input(&inputs[6]),
        get_input(&inputs[7]),
    };

    const INPUT_INTERACT = 0;
    const INPUT_CONFIRM = 1;
    const INPUT_TAB_LF = 2;
    const INPUT_TAB_RT = 3;

    fn get_input(comptime input: *MenuInput) InputGetFnType {
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
        .items = .{ .it = @ptrCast(&MenuItems), .len = MenuItems.len },
        .inputs = .{ .cb = @ptrCast(&InputList), .len = InputList.len },
        .callback = MainCallback,
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

    var MenuItems = [_]m.MenuItem{
        m.MenuItemRange(&values.fps, "FPS", 10, 500, true, CallbackFps),
        m.MenuItemSpacer(),
        m.MenuItemList(&values.vehicle, "Vehicle", &rv.VehicleNames, true, CallbackVehicle),
        // FIXME: maybe change to menu order?
        m.MenuItemList(&values.track, "Track", &rtr.TrackNameById, true, CallbackTrack),
        m.MenuItemSpacer(),
        m.MenuItemList(&values.up_lv[0], rv.UpgradeNames[0], rv.PartNameS(0), false, CallbackUpgrade),
        m.MenuItemList(&values.up_lv[1], rv.UpgradeNames[1], rv.PartNameS(1), false, CallbackUpgrade),
        m.MenuItemList(&values.up_lv[2], rv.UpgradeNames[2], rv.PartNameS(2), false, CallbackUpgrade),
        m.MenuItemList(&values.up_lv[3], rv.UpgradeNames[3], rv.PartNameS(3), false, CallbackUpgrade),
        m.MenuItemList(&values.up_lv[4], rv.UpgradeNames[4], rv.PartNameS(4), false, CallbackUpgrade),
        m.MenuItemList(&values.up_lv[5], rv.UpgradeNames[5], rv.PartNameS(5), false, CallbackUpgrade),
        m.MenuItemList(&values.up_lv[6], rv.UpgradeNames[6], rv.PartNameS(6), false, CallbackUpgrade),
        m.MenuItemSpacer(),
        m.MenuItemToggle(&values.mirror, "Mirror", null),
        m.MenuItemRange(&values.laps, "Laps", 1, 5, true, null),
        m.MenuItemRange(&values.racers, "Racers", 1, 12, true, null),
        m.MenuItemList(&values.ai_speed, "AI Speed", &[_][*:0]const u8{ "Slow", "Average", "Fast" }, true, null),
        //m.MenuItemList(&values.winnings_split, "Winnings", &[_][]const u8{ "Fair", "Skilled", "Winner Takes All" }, true),
        m.MenuItemSpacer(),
        // FIXME: add toggle to ingame start race menu too
        m.MenuItemToggle(&values.n64_pitch, "N64 Pitch", CallbackN64Pitch),
        m.MenuItemSpacer(),
        m.MenuItemButton("Race!", CallbackRaceButton),
    };

    fn load_race() void {
        if (h_s_fps_default) |h| gf.ASettingUpdate(h, .{ .u = @intCast(values.fps) });
        if (QolState.h_s_default_laps) |h| gf.ASettingUpdate(h, .{ .u = @intCast(values.laps) });
        if (QolState.h_s_default_racers) |h| gf.ASettingUpdate(h, .{ .u = @intCast(values.racers) });

        // NOTE: laps, racers handled by settings update fn
        FpsTimer.SetPeriod(@intCast(values.fps));
        _ = mem.write(0xE35A84, u8, @as(u8, @intCast(values.vehicle))); // file slot 0 - character
        var hang = re.Manager.entity(.Hang, 0);
        hang.VehiclePlayer = @intCast(values.vehicle);
        hang.Track = @intCast(values.track);
        if (using_circuit_track_order) hang.Track = rtr.TrackMenuIdMap[hang.Track];
        hang.Circuit = rtr.TrackCircuitIdMap[@intCast(values.track)];
        hang.Mirror = @intCast(values.mirror);
        hang.AISpeed = @intCast(values.ai_speed + 1);
        for (0..7) |i| {
            rrd.pPlayer.*.?.pFile.?.upgrade_lv[i] = @intCast(values.up_lv[i]);
            rrd.pPlayer.*.?.pFile.?.upgrade_hp[i] = @intCast(values.up_hp[i]);
        }

        PatchN64Pitch(values.n64_pitch != 0);
        values.n64_pitch_applied = values.n64_pitch;

        RestartRace(false);
        close();
    }

    // TODO: repurpose to run every EventJdgeBegn, maybe add different init if
    // that introduces issues with state loop
    fn init() void {
        const hang = re.Manager.entity(.Hang, 0);
        values.vehicle = hang.VehiclePlayer;
        values.track = if (using_circuit_track_order) rtr.TrackIdMenuMap[hang.Track] else hang.Track;
        values.mirror = hang.Mirror;
        values.laps = hang.Laps;
        values.racers = hang.Racers;
        values.ai_speed = hang.AISpeed - 1;
        //values.ai_speed = hang.Winnings;
        for (0..7) |i| {
            values.up_lv[i] = rrd.pPlayer.*.?.pFile.?.upgrade_lv[i];
            values.up_hp[i] = rrd.pPlayer.*.?.pFile.?.upgrade_hp[i];
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
        gf.ASettingSaveAuto();
        if (!gf.GFreezeOff()) return;
        rso.swrSound_PlaySound(77, 6, 0.25, 1.0, 0);
        rg.PAUSE_STATE.* = 3;
        menu_active.update(false);
    }

    // FIXME: menu not opening bug when reloading plugin can probably be solved
    //  by checking for inrace+!initialized here
    fn update() void {
        if (gf.SInRace() == .JustOn)
            init();

        if (!gf.SInRace().on() or !initialized) return;

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

    fn MainCallback(menu: *Menu) callconv(.C) bool {
        var result = false;
        if (menu.inputs.cb) |cb| {
            // confirm from anywhere
            if (cb[INPUT_CONFIRM](.JustOn) and menu_active == .On) {
                load_race();
                return false;
            }
        }
        return result;
    }

    fn CallbackUpgrade(menu: *Menu, _: *MenuItem) callconv(.C) bool {
        if (menu.inputs.cb) |cb| {
            // set all to NU
            if (cb[INPUT_TAB_LF](.JustOn)) {
                values.up_lv = comptime [_]i32{0} ** 7;
                return true;
            }
            // set all to MU
            if (cb[INPUT_TAB_RT](.JustOn)) {
                values.up_lv = comptime [_]i32{5} ** 7;
                return true;
            }
        }
        return false;
    }

    // TODO: higher options if moving cap to 1000fps later
    // TODO: user-defined preset, maybe
    const FpsPresets = [_]i32{ 24, 30, 48, 60, 120, 144, 165, 240, 360, 480 };

    fn CallbackFps(menu: *Menu, item: *MenuItem) callconv(.C) bool {
        if (menu.inputs.cb) |cb| {
            // scroll presets
            if (cb[INPUT_TAB_LF](.JustOn)) {
                const i = bmem.lastIndexOfScalarSmaller(i32, &FpsPresets, values.fps);
                values.fps = if (i) |ii| FpsPresets[ii] else item.min;
                return true;
            }
            if (cb[INPUT_TAB_RT](.JustOn)) {
                const i = bmem.indexOfScalarGreater(i32, &FpsPresets, values.fps);
                values.fps = if (i) |ii| FpsPresets[ii] else item.max;
                return true;
            }

            // save without restarting
            if (cb[INPUT_INTERACT](.JustOn) and gf.SPracticeMode()) {
                FpsTimer.SetPeriod(@intCast(values.fps));
                if (h_s_fps_default) |h|
                    gf.ASettingUpdate(h, .{ .u = @intCast(values.fps) });

                rso.swrSound_PlaySoundMacro(45); // sfx_vox_pdroid_i1.wav
            }
        }
        return false;
    }

    // TODO: test: wrapping favourites
    // TODO: test: pressing jump/tab input actually goes to a favourite
    // TODO: test: pressing jump/tab input scrolls to next pod if no favourites set
    // TODO: add color to vehicle names when they are favorited
    // TODO: implement this behaviour on normal vehicle select
    fn CallbackVehicle(menu: *Menu, _: *MenuItem) callconv(.C) bool {
        if (menu.inputs.cb) |cb| {
            // scroll favorites
            if (cb[INPUT_TAB_LF](.JustOn)) {
                const bitmask = s_favorite_vehicles & 0x7FFFFF;
                if (bitmask == 0) {
                    values.vehicle = @mod(values.vehicle - 1, 23);
                    return true;
                }
                const i = bmem.lastBitIndexOfSmaller(u32, bitmask, @intCast(values.vehicle));
                values.vehicle = @intCast(i orelse (31 - @clz(bitmask)));
                return true;
            }
            if (cb[INPUT_TAB_RT](.JustOn)) {
                const bitmask = s_favorite_vehicles & 0x7FFFFF;
                if (bitmask == 0) {
                    values.vehicle = @mod(values.vehicle + 1, 23);
                    return true;
                }
                const i = bmem.bitIndexOfGreater(u32, bitmask, @intCast(values.vehicle));
                values.vehicle = @intCast(i orelse @ctz(bitmask));
                return true;
            }

            // interact = toggle favorite
            if (cb[INPUT_INTERACT](.JustOn)) {
                const vehicle_bit: u32 = @as(u32, 1) << @intCast(values.vehicle);
                if (h_s_favorite_vehicles) |h|
                    gf.ASettingUpdate(h, .{ .u = s_favorite_vehicles ^ vehicle_bit });

                var sound_id: i16 = 44; // sfx_vox_pdroid_h2.wav
                if (s_favorite_vehicles & vehicle_bit > 0) sound_id = 45; // sfx_vox_pdroid_i1.wav
                rso.swrSound_PlaySoundMacro(sound_id);
            }
        }
        return false;
    }

    // TODO: circuit-based presets, if/when circuit order added
    // TODO: highlight color changing depending on planet?
    const TrackPresetsPlanet = [_:0]i32{
        rtr.THE_BOONTA_TRAINING_COURSE,
        rtr.BEEDOS_WILD_RIDE,
        rtr.AQUILARIS_CLASSIC,
        rtr.SCRAPPERS_RUN,
        rtr.BAROO_COAST,
        rtr.MON_GAZZA_SPEEDWAY,
        rtr.VENGEANCE,
        rtr.MALASTARE_100,
    };

    const TrackPresetsCircuit = [_:0]i32{
        rtr.TrackIdMenuMap[rtr.THE_BOONTA_TRAINING_COURSE],
        rtr.TrackIdMenuMap[rtr.SUNKEN_CITY],
        rtr.TrackIdMenuMap[rtr.SEBULBAS_LEGACY],
        rtr.TrackIdMenuMap[rtr.ANDO_PRIME_CENTRUM],
    };

    var TrackPresets: []const i32 = &TrackPresetsPlanet;

    fn set_track_order(circuit: bool) void {
        if (circuit == using_circuit_track_order) return;
        defer using_circuit_track_order = circuit;

        // FIXME: more robust way of making sure we are referencing the
        //  correct menu item
        // at this point, we know we need to remap either way
        const it: *MenuItem = &MenuItems[3];
        assert(std.mem.eql(u8, "Track", std.mem.span(it.label.?)));
        if (circuit) {
            TrackPresets = &TrackPresetsCircuit;
            values.track = rtr.TrackIdMenuMap[@intCast(values.track)];
            it.options = &rtr.TrackNameByMenu;
        } else {
            TrackPresets = &TrackPresetsPlanet;
            values.track = rtr.TrackMenuIdMap[@intCast(values.track)];
            it.options = &rtr.TrackNameById;
        }
    }

    fn CallbackTrack(menu: *Menu, _: *MenuItem) callconv(.C) bool {
        if (menu.inputs.cb) |cb| {
            // scroll presets
            if (cb[INPUT_TAB_LF](.JustOn)) {
                const i = bmem.lastIndexOfScalarSmaller(i32, TrackPresets, values.track);
                values.track = TrackPresets[i orelse TrackPresets.len - 1];
                return true;
            }
            if (cb[INPUT_TAB_RT](.JustOn)) {
                const i = bmem.indexOfScalarGreater(i32, TrackPresets, values.track);
                values.track = TrackPresets[i orelse 0];
                return true;
            }
            if (cb[INPUT_INTERACT](.JustOn)) {
                set_track_order(!using_circuit_track_order);

                // 44 = sfx_vox_pdroid_h2.wav
                // 45 = sfx_vox_pdroid_i1.wav
                var sound_id: i16 = if (using_circuit_track_order) 44 else 45;
                rso.swrSound_PlaySoundMacro(sound_id);

                if (h_s_menu_track_order) |h|
                    gf.ASettingUpdate(h, .{ .str = if (!using_circuit_track_order) "PLANET" else "CIRCUIT" });

                return false;
            }
        }
        return false;
    }

    fn CallbackN64Pitch(_: *Menu, _: *MenuItem) callconv(.C) bool {
        if (values.n64_pitch != values.n64_pitch_applied) {
            PatchN64Pitch(values.n64_pitch != 0);
            values.n64_pitch_applied = values.n64_pitch;
        }
        return false;
    }

    fn CallbackRaceButton(menu: *Menu, _: *MenuItem) callconv(.C) bool {
        if (menu.inputs.cb) |cb| {
            if (cb[INPUT_INTERACT](.JustOn)) {
                load_race();
            }
        }
        return false;
    }
};

// MISC.

// TODO: confirm there is no case where jdge would not be initialized
// TODO: validate in-race??
fn RestartRace(play_sound: bool) void {
    if (0 != re.Jdge.LOAD_QUEUED.*) return;

    const jdge = re.Manager.entity(.Jdge, 0);
    if (!re.Jdge.hCouldPause(jdge)) return;

    const is_paused = re.Jdge.PAUSE_MENU_STATE.* > 0;
    if (is_paused) re.Jdge.fnPauseMenuClose();

    if (!is_paused and play_sound) rso.swrSound_PlaySound(77, 6, 0.25, 1.0, 0);
    re.Jdge.fnQueueLoad(jdge, re.M_RSTR);
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

export fn OnInit(gf: *GlobalFn) callconv(.C) void {
    // NOTE: keep at top
    QuickRaceMenu.gf = gf;

    _ = ShowCursor(0); // cursor fix
    QolState.settingsInit(gf);

    PatchCameraFKeys(true);

    PatchJinnReesoCheat(true);
    PatchCyYungaCheat(true);
    PatchCyYungaCheatAudio(true);
    PatchTrugutsCheat(true);
}

export fn OnInitLate(_: *GlobalFn) callconv(.C) void {
    var hang = re.Manager.entity(.Hang, 0);

    // TODO: look into using in-game default setter as hook, see fn_45BD90
    // TODO: change annodue setting to i32 for both, also look into anywhere
    // else like this that might have been affected by new Hang stuff
    hang.Laps = @intCast(QolState.s_default_laps);
    _ = mem.write(0x50C558, i8, @as(i8, @intCast(QolState.s_default_racers))); // racers

    if (QolState.s_trackselect_remember) {
        hang.Track = @truncate(QolState.s_trackselect_last);
        hang.Circuit = rtr.TrackCircuitIdMap[QolState.s_trackselect_last];
    }
}

export fn OnDeinit(_: *GlobalFn) callconv(.C) void {
    QuickRaceMenu.FpsTimer.End();
    QuickRaceMenu.close();
    PatchN64Pitch(false);

    PatchJinnReesoCheat(false);
    PatchCyYungaCheat(false);
    PatchCyYungaCheatAudio(false);
    PatchTrugutsCheat(false);

    PatchCameraFKeys(false);

    PatchRaceTimerMsHud(false);
    PatchRaceTimerMsFinish(false);
    PatchPlanetCutscenes(false);
    PatchPodiumCutscene(false);
    PatchViewportEdges(false);
    PatchWindowBackgroundActivity(false);
    PatchTrackSelectEntry(false);
    PatchMenuNavigationSpeed(false);
    _ = mem.write(0x4525AE, u8, 1); // undo 'default_camera'

    FastCountdown.patch(false);
}

// HOOKS

export fn InputUpdateB(gf: *GlobalFn) callconv(.C) void {
    QolState.UpdateInput(gf);
    QuickRaceMenu.update_input();
}

export fn InputUpdateA(_: *GlobalFn) callconv(.C) void {
    // add dpad input to menu navigation
    if (QolState.s_dpad_navigation and ri.JOYSTICK_DEVICE_COUNT.* > 0) {
        // TODO: convert to object ref instead of building joy_index manually, after
        // typedef done in racerlib/Input
        const joy_index: u32 = 0x100 + 0x20 * ri.JOYSTICK_DEVICE_ACTIVE.* + 0x10;

        var off_x: i16 = 0;
        off_x -= @intCast(ri.RAW_STATE_ON.*[joy_index + 0] * 100); // lf
        off_x += @intCast(ri.RAW_STATE_ON.*[joy_index + 2] * 100); // rt
        if (off_x != 0)
            ri.PACKING_BUFFER[0].AxisX = @divTrunc(ri.PACKING_BUFFER[0].AxisX + off_x, 2);

        var off_y: i16 = 0;
        off_y += @intCast(ri.RAW_STATE_ON.*[joy_index + 1] * 100); // up
        off_y -= @intCast(ri.RAW_STATE_ON.*[joy_index + 3] * 100); // dn
        if (off_y != 0)
            ri.PACKING_BUFFER[0].AxisY = @divTrunc(ri.PACKING_BUFFER[0].AxisY + off_y, 2);
    }
}

export fn InputUpdateKeyboardA(_: *GlobalFn) callconv(.C) void {
    // map xinput start to esc
    const start_on: u32 = @intFromBool(QolState.input_pause.gets() == .On);
    const start_just_on: u32 = @intFromBool(QolState.input_pause.gets() == .JustOn);
    _ = mem.write(ri.RAW_STATE_ON_ADDR + 4, u32, start_on);
    _ = mem.write(ri.RAW_STATE_JUST_ON_ADDR + 4, u32, start_just_on);
}

export fn TimerUpdateB(gf: *GlobalFn) callconv(.C) void {
    if (gf.SInRace().on() and QolState.s_fps_limiter and rti.STOPPED.* == 0)
        QuickRaceMenu.FpsTimer.Sleep();
}

export fn TimerUpdateA(_: *GlobalFn) callconv(.C) void {
    FastCountdown.update();
}

export fn MenuTrackB(gf: *GlobalFn) callconv(.C) void {
    const hang = re.Manager.entity(.Hang, 0);

    const laps: u32 = @intCast(hang.Laps);
    if (QolState.h_s_default_laps != null and laps != QolState.s_default_laps)
        gf.ASettingUpdate(QolState.h_s_default_laps.?, .{ .u = laps });

    const racers: u32 = @intCast(mem.read(0x50C558, i8));
    if (QolState.h_s_default_racers != null and racers != QolState.s_default_racers)
        gf.ASettingUpdate(QolState.h_s_default_racers.?, .{ .u = racers });

    // FIXME: convert to mapped inputs
    if (QolState.s_clear_records_enable and gf.InputGetKbRaw(.BACK) == .JustOn) {
        var buf: [127:0]u8 = undefined;
        if (gf.InputGetKbRaw(.@"1").on()) {
            rs.BestTimeClear(rs.GameSaveData, hang.Track, 1, hang.Mirror != 0);
            _ = std.fmt.bufPrintZ(&buf, "{s} Best Lap cleared", .{rtr.TrackNameById[hang.Track]}) catch return;
            _ = gf.ToastNew(&buf, rt.ColorRGB.Red.rgba(0));
        }
        if (gf.InputGetKbRaw(.@"3").on()) {
            rs.BestTimeClear(rs.GameSaveData, hang.Track, 3, hang.Mirror != 0);
            _ = std.fmt.bufPrintZ(&buf, "{s} 3-Lap Record cleared", .{rtr.TrackNameById[hang.Track]}) catch return;
            _ = gf.ToastNew(&buf, rt.ColorRGB.Red.rgba(0));
        }
    }
}

export fn EarlyEngineUpdateB(gf: *GlobalFn) callconv(.C) void {
    // Fast Menu Navigation
    if (QolState.s_fast_navigation) {
        const hang = re.Manager.entity(.Hang, 0);
        if (hang.MenuScreen != hang.MenuScreenPrev)
            PatchMenuNavigationSpeedTransitions(true);
    }

    // FIXME: settings toggles for both of these
    // FIXME: probably want this mid-engine update, immediately before Jdge gets
    // processed? (a fn in EngineUpdateStage14 iirc)

    // Quick Restart
    if (gf.SInRace().on() and
        QolState.s_quickstart and
        !QuickRaceMenu.menu_active.on() and
        ((QolState.input_quickstart.gets().on() and QolState.input_pause.gets() == .JustOn) or
        (QolState.input_quickstart.gets() == .JustOn and QolState.input_pause.gets().on())))
    {
        RestartRace(true);
        return; // skip quick race menu
    }

    // Quick Race Menu
    if (QolState.s_quickrace)
        QuickRaceMenu.update();
}

// FIXME: investigate - used to be TextRenderB, but that doesn't run every frame
// however, the text flushing DOES run on those frames, apparently from a different callsite
export fn EarlyEngineUpdateA(gf: *GlobalFn) callconv(.C) void {
    const hang = re.Manager.entity(.Hang, 0);
    const jdge = re.Manager.entity(.Jdge, 0);

    if (QolState.h_s_trackselect_last != null and QolState.s_trackselect_last != hang.Track)
        gf.ASettingUpdate(QolState.h_s_trackselect_last.?, .{ .u = hang.Track });

    if (gf.SInRace().on()) {
        if (gf.SRaceStateNew() and gf.SRaceState() == .PreRace)
            race.reset();

        if (QolState.s_default_camera_auto and gf.SRaceState() == .Racing) {
            if (QolState.cam_cman == null or gf.SRaceStateNew())
                QolState.cam_cman = re.cMan.FindFromPlayerEntity(re.Test.pPlayer.*.?);

            if (QolState.cam_cman) |cman| {
                if (cman.mode != QolState.cam_prev and cman.mode != QolState.s_default_camera and
                    (cman.mode == 1 or cman.mode == 2 or cman.mode == 4 or cman.mode == 5))
                    if (QolState.h_s_default_camera) |h| gf.ASettingUpdate(h, .{ .u = cman.mode });
                QolState.cam_prev = cman.mode;
            }
        }

        const total_time: f32 = rrd.pPlayer.*.?.time.total;

        if (gf.SRaceState() == .Countdown) {
            race.update_position();
        }

        if (gf.SRaceState() == .Racing or (gf.SRaceStateNew() and gf.SRaceState() == .PostRace)) {
            const p = re.Test.pPlayer.*.?;

            // stats

            const speed = p.speed;
            race.update_position();
            const this_distance = race.this_position.distance(&race.prev_position);
            race.set_motion(total_time, speed, this_distance);

            if (gf.SPlayerBoosting() == .JustOn) race.set_last_boost_start(total_time);
            if (gf.SPlayerBoosting().on()) race.set_total_boost(total_time, this_distance);
            if (gf.SPlayerBoosting() == .JustOff) race.set_total_boost(total_time, this_distance);

            if (gf.SPlayerUnderheating() == .JustOn) race.set_last_underheat_start(total_time);
            if (gf.SPlayerUnderheating().on()) race.set_total_underheat(total_time);
            if (gf.SPlayerUnderheating() == .JustOff) race.set_total_underheat(total_time);

            if (gf.SPlayerOverheating() == .JustOn) race.set_last_overheat_start(total_time);
            if (gf.SPlayerOverheating().on()) race.set_total_overheat(total_time);
            if (gf.SPlayerOverheating() == .JustOff) race.set_total_overheat(total_time);
            if (gf.SPlayerOverheating().on() and gf.SRaceState() == .PostRace)
                race.set_fire_finish_duration(total_time);

            // auto reset

            if (QolState.s_autoreset_enable) autoreset: {
                var reset_race = false;

                defer if (reset_race) {
                    RestartRace(true);
                    QolState.autoreset_dead.update(false);
                    QolState.autoreset_has_boost_charged = false;
                    QolState.autoreset_has_boost_boosted = false;
                    QolState.autoreset_dead_timer = 0;
                    QolState.autoreset_fire_timer = 0;
                    QolState.autoreset_firstboost_timer = 0;
                    QolState.autoreset_underheat_timer = 0;
                };

                if (QolState.s_autoreset_dead_enable) {
                    QolState.autoreset_dead.update(p.flags1.IS_DEAD or
                        p.flags2.IS_EXPLODING or
                        p.flags2.IS_EXPLODING_RIGHT_SPIN or
                        p.flags2.IS_EXPLODING_LEFT_SPIN);
                    if (QolState.autoreset_dead == .JustOn)
                        QolState.autoreset_dead_timer = 0;
                    if (QolState.autoreset_dead.on()) {
                        QolState.autoreset_dead_timer += rti.FRAMETIME.*;
                        if (QolState.autoreset_dead_timer >= QolState.s_autoreset_dead_delay) {
                            reset_race = true;
                            break :autoreset;
                        }
                    }
                }

                if (QolState.s_autoreset_fire_enable) {
                    if (gf.SPlayerOverheating() == .JustOn)
                        QolState.autoreset_fire_timer = 0;
                    if (gf.SPlayerOverheating().on()) {
                        QolState.autoreset_fire_timer += rti.FRAMETIME.*;
                        if (QolState.autoreset_fire_timer >= QolState.s_autoreset_fire_delay) {
                            reset_race = true;
                            break :autoreset;
                        }
                    }
                }

                if (QolState.s_autoreset_firstboost_enable and !QolState.autoreset_has_boost_boosted) blk: {
                    if (gf.SPlayerBoosting() == .JustOn) {
                        QolState.autoreset_firstboost_timer = 0;
                        QolState.autoreset_has_boost_boosted = true;
                        break :blk;
                    }

                    if (gf.SPlayerBoostReady() == .JustOn)
                        QolState.autoreset_has_boost_charged = true;

                    if (QolState.autoreset_has_boost_charged) {
                        QolState.autoreset_firstboost_timer += rti.FRAMETIME.*;
                        if (QolState.autoreset_firstboost_timer >= QolState.s_autoreset_firstboost_delay) {
                            reset_race = true;
                            break :autoreset;
                        }
                    }
                }

                if (QolState.s_autoreset_underheat_enable and QolState.autoreset_has_boost_boosted) {
                    if (gf.SPlayerUnderheating() == .JustOn)
                        QolState.autoreset_underheat_timer = 0;
                    if (gf.SPlayerUnderheating().on()) {
                        QolState.autoreset_underheat_timer += rti.FRAMETIME.*;
                        if (QolState.autoreset_underheat_timer >= QolState.s_autoreset_underheat_delay) {
                            reset_race = true;
                            break :autoreset;
                        }
                    }
                }
            }
        }

        if (gf.SRaceState() == .PostRace and !gf.GHideRaceUIIsOn()) {
            // summary readout thing
            const upg_postfix = if (rrd.GetPlayerUsingUpgrades()) "" else "  NU";
            RenderRaceResultHeader(gf, 0, "{d:>2.0}/{s}{s}", .{
                gf.SFPSAvg(),
                rv.PartNamesShort[rrd.pPlayer.*.?.pFile.?.upgrade_lv[0]],
                upg_postfix,
            });

            for (0..7) |i| RenderRaceResultStatUpgrade(
                gf,
                2 + @as(u8, @truncate(i)),
                @as(u8, @truncate(i)),
                rrd.pPlayer.*.?.pFile.?.upgrade_lv[i],
                rrd.pPlayer.*.?.pFile.?.upgrade_hp[i],
            );

            RenderRaceResultStatF(gf, 10, "Top Speed", race.top_speed);
            RenderRaceResultStatF(gf, 11, "Avg Speed", race.avg_speed);
            RenderRaceResultStatF(gf, 12, "Distance", race.total_distance);
            RenderRaceResultStatU(gf, 13, "Deaths", gf.SPlayerDeaths());

            // zig fmt: off
            RenderRaceResultStatU(gf,    15, "Boosts",          race.total_boosts);
            RenderRaceResultStatTime(gf, 16, "First Boost",     race.first_boost_time);
            RenderRaceResultStatTime(gf, 17, "Fire Finish",     race.fire_finish_duration);
            RenderRaceResultStatTime(gf, 18, "Underheat Time",  race.total_underheat);
            RenderRaceResultStatTime(gf, 19, "Overheat Time",   race.total_overheat);
            RenderRaceResultStatTime(gf, 20, "Boost Time",      race.total_boost_duration);
            RenderRaceResultStatTime(gf, 21, "Avg Boost Time",  race.avg_boost_duration);
            RenderRaceResultStatF(gf,    22, "Boost Dist",      race.total_boost_distance);
            RenderRaceResultStatF(gf,    23, "Avg Boost Dist",  race.avg_boost_distance);
            RenderRaceResultStatF(gf,    24, "Boost Ratio",     race.total_boost_ratio);
            // zig fmt: on

            // show detailed lap times
            if (QolState.s_show_postrace_times_hex) {
                const color: u32 = 0xCCCCCCBE;
                const line_height: i16 = 28;
                const x: i16 = 50;
                var y: i16 = 305 + (5 - @as(i16, @intCast(jdge.*.Laps))) * line_height;
                for (&rrd.pPlayer.*.?.time.lap) |t| {
                    if (t < 0) break;
                    _ = gf.GDrawText(.Overlay, rt.hMakeText(x, y, "{X:0>8}", .{
                        @as(u32, @bitCast(t)),
                    }, color, null) catch null);
                    y += line_height;
                }
                _ = gf.GDrawText(.Overlay, rt.hMakeText(x, y, "{X:0>8}", .{
                    @as(u32, @bitCast(rrd.pPlayer.*.?.time.total)),
                }, color, null) catch null);
            }
        }
    }
}

export fn MapRenderB(_: *GlobalFn) callconv(.C) void {
    // TODO: move to core? since it only matters with running annodue
    rt.bTextHiRes.* = 0;
}
