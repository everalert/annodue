const Self = @This();

const GlobalState = @import("SharedDef.zig").GlobalState;
const GlobalFunction = @import("SharedDef.zig").GlobalFunction;

const std = @import("std");
const win = std.os.windows;

const draw = @import("GDraw.zig");
const freeze = @import("GFreeze.zig");
const hide_race_ui = @import("GHideRaceUI.zig");
const toast = @import("Toast.zig");
const input = @import("Input.zig");
const asettings = @import("ASettings.zig");
const settings = @import("Settings.zig");
const s = settings.SettingsState;
const rterrain = @import("RTerrain.zig");
const rtrigger = @import("RTrigger.zig");

const st = @import("../util/active_state.zig");
const xinput = @import("../util/xinput.zig");
const dbg = @import("../util/debug.zig");
const msg = @import("../util/message.zig");
const mem = @import("../util/memory.zig");

const app = @import("../appinfo.zig");
const VERSION = app.VERSION;
const VERSION_STR = app.VERSION_STR;

const rti = @import("racer").Time;
const rg = @import("racer").Global;
const rrd = @import("racer").RaceData;
const re = @import("racer").Entity;
const rt = @import("racer").Text;
const rto = rt.TextStyleOpts;

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;
const w32xc = w32.ui.input.xbox_controller;
const w32wm = w32.ui.windows_and_messaging;
const POINT = w32.foundation.POINT;
const KS_DOWN: i16 = -1;
const KS_PRESSED: i16 = 1; // since last call

// NOTE: may want to figure out all the code caves in .data for potential use
// TODO: split up the versioning, global structs, etc. from the business logic

// STATE

fn global_player_reset(self: *GlobalState) void {
    const p = &self.player;
    p.upgrades_lv = rrd.PLAYER.*.pFile.upgrade_lv; // TODO: remove from gs, now that it's easy?
    p.upgrades_hp = rrd.PLAYER.*.pFile.upgrade_hp; // TODO: remove from gs, now that it's easy?
    p.upgrades = for (0..7) |i| {
        if (p.upgrades_lv[i] > 0 and p.upgrades_hp[i] > 0) break true;
    } else false;

    p.flags1 = 0;
    p.boosting = .Off;
    p.underheating = .On; // you start the race underheating
    p.overheating = .Off;
    p.dead = .Off;
    p.deaths = 0;

    p.heat_rate = re.Test.PLAYER.*.stats.HeatRate; // TODO: remove from gs, now that it's easy?
    p.cool_rate = re.Test.PLAYER.*.stats.CoolRate; // TODO: remove from gs, now that it's easy?
    p.heat = 0;
}

fn global_player_update(self: *GlobalState) void {
    const p = &self.player;
    p.flags1 = re.Test.PLAYER.*.flags1; // TODO: remove from gs, now that it's easy?
    p.heat = re.Test.PLAYER.*.temperature; // TODO: remove from gs, now that it's easy?
    const engine = re.Test.PLAYER.*.engineStatus; // TODO: remove from gs, now that it's easy?

    p.boosting.update((p.flags1 & (1 << 23)) > 0);
    p.underheating.update(p.heat >= 100);
    p.overheating.update(for (0..6) |i| {
        if (engine[i] & (1 << 3) > 0) break true;
    } else false);
    p.dead.update((p.flags1 & (1 << 14)) > 0);
    if (p.dead == .JustOn) p.deaths += 1;
}

pub var GLOBAL_STATE: GlobalState = .{};

pub var GLOBAL_FUNCTION: GlobalFunction = .{
    // Settings
    .ASettingOccupy = &asettings.ASettingOccupy,
    .ASettingVacate = &asettings.ASettingVacate,
    .ASettingVacateAll = &asettings.AVacateAll,
    .ASettingUpdate = &asettings.ASettingUpdate,
    .ASettingResetAllDefault = &asettings.ASettingResetAllDefault,
    .ASettingResetAllFile = &asettings.ASettingResetAllFile,
    .ASettingCleanAll = &asettings.ASettingCleanAll,
    .ASettingSectionOccupy = &asettings.ASectionOccupy,
    .ASettingSectionVacate = &asettings.ASectionVacate,
    .ASettingSectionRunUpdate = &asettings.ASectionRunUpdate,
    .ASettingSectionResetDefault = &asettings.ASectionResetDefault,
    .ASettingSectionResetFile = &asettings.ASectionResetFile,
    .ASettingSectionClean = &asettings.ASectionClean,
    .SettingGetB = &settings.get_bool,
    .SettingGetI = &settings.get_i32,
    .SettingGetU = &settings.get_u32,
    .SettingGetF = &settings.get_f32,
    // Input
    .InputGetKb = &input.get_kb,
    .InputGetKbRaw = &input.get_kb_raw,
    .InputGetMouse = &input.get_mouse_raw,
    .InputGetMouseDelta = &input.get_mouse_raw_d,
    .InputLockMouse = &input.lock_mouse,
    //InputGetMouseInWindow= &input.get_mouse_inside,
    .InputGetXInputButton = &input.get_xinput_button,
    .InputGetXInputAxis = &input.get_xinput_axis,
    // Game
    .GDrawText = &draw.GDrawText,
    //.GDrawTextBox = &draw.GDrawTextBox,
    .GDrawRect = &draw.GDrawRect,
    .GDrawRectBdr = &draw.GDrawRectBdr,
    .GFreezeOn = &freeze.GFreezeOn,
    .GFreezeOff = &freeze.GFreezeOff,
    .GFreezeIsOn = &freeze.GFreezeIsOn,
    .GHideRaceUIOn = &hide_race_ui.GHideRaceUIOn,
    .GHideRaceUIOff = &hide_race_ui.GHideRaceUIOff,
    .GHideRaceUIIsOn = &hide_race_ui.GHideRaceUIIsOn,
    // Toast
    .ToastNew = &toast.ToastSystem.NewToast,
    // Resources
    .RTerrainRequest = &rterrain.RRequest,
    .RTerrainRelease = &rterrain.RRelease,
    .RTerrainReleaseAll = &rterrain.RReleaseAll,
    .RTriggerRequest = &rtrigger.RRequest,
    .RTriggerRelease = &rtrigger.RRelease,
    .RTriggerReleaseAll = &rtrigger.RReleaseAll,
};

// UTIL

const style_practice_label = rt.MakeTextHeadStyle(.Default, true, .Yellow, .Right, .{rto.ToggleShadow}) catch "";

fn DrawMenuPracticeModeLabel() void {
    _ = GLOBAL_FUNCTION.GDrawText(
        .SystemP,
        rt.MakeText(640 - 20, 16, "Practice Mode", .{}, 0xFFFFFFFF, style_practice_label) catch null,
    );
}

fn DrawVersionString() void {
    _ = GLOBAL_FUNCTION.GDrawText(
        .System,
        rt.MakeText(36, 480 - 24, "{s}", .{VERSION_STR}, 0xFFFFFFFF, null) catch null,
    );
}

// INIT

pub fn init() bool {
    const kb_shift: i16 = w32kb.GetAsyncKeyState(@intFromEnum(w32kb.VK_SHIFT));
    const kb_shift_dn: bool = (kb_shift & KS_DOWN) != 0;
    if (kb_shift_dn)
        return false;

    // TODO: remove? probably don't need these anymore lol
    GLOBAL_STATE.hwnd = rg.HWND.*;
    GLOBAL_STATE.hinstance = rg.HINSTANCE.*;

    return true;
}

// HOOK CALLS

pub fn OnInit(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {}

pub fn OnInitLate(gs: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    gs.init_late_passed = true;
}

pub fn OnDeinit(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {}

pub fn EngineUpdateStage14A(gs: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    const player_ready: bool = rrd.PLAYER_PTR.* != 0 and rrd.PLAYER.*.pTestEntity != 0;
    gs.in_race.update(player_ready);

    gs.race_state_prev = gs.race_state;
    gs.race_state = blk: {
        if (!gs.in_race.on()) break :blk .None;
        if (rg.IN_RACE.* == 0) break :blk .PreRace;
        // TODO: figure out how the engine knows to set these and use those instead
        const flags1 = re.Test.PLAYER.*.flags1;
        const countdown: bool = flags1 & (1 << 0) != 0;
        if (countdown) break :blk .Countdown;
        const postrace: bool = flags1 & (1 << 5) == 0;
        const show_stats: bool = re.Manager.entity(.Jdge, 0).Flags & 0x0F == 2;
        if (postrace and show_stats) break :blk .PostRace;
        if (postrace) break :blk .PostRaceExiting;
        break :blk .Racing;
    };
    gs.race_state_new = gs.race_state != gs.race_state_prev;

    if (gs.race_state_new and gs.race_state == .PreRace) global_player_reset(gs);
    if (gs.in_race.on()) global_player_update(gs);
}

pub fn TimerUpdateA(gs: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    gs.dt_f = rti.FRAMETIME.*;
    gs.fps = rti.FPS.*;
    const fps_res: f32 = 1 / gs.dt_f * 2;
    gs.fps_avg = (gs.fps_avg * (fps_res - 1) + (1 / gs.dt_f)) / fps_res;
    gs.timestamp = rti.TIMESTAMP.*;
    gs.framecount = rti.FRAMECOUNT.*;
}

pub fn MenuTitleScreenB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    // TODO: make text only appear on the actual title screen, i.e. remove from file select etc.
    DrawVersionString();
    DrawMenuPracticeModeLabel();
}

pub fn MenuStartRaceB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuRaceResultsB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuTrackSelectB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuTrackB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}
