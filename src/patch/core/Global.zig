const Self = @This();

const GlobalState = @import("SharedDef.zig").GlobalState;
const GlobalFunction = @import("SharedDef.zig").GlobalFunction;
const RaceState = @import("SharedDef.zig").RaceState;

const std = @import("std");

const draw = @import("GDraw.zig");
const freeze = @import("GFreeze.zig");
const hide_race_ui = @import("GHideRaceUI.zig");
const toast = @import("Toast.zig");
const input = @import("Input.zig");
const asettings = @import("ASettings.zig");
const rterrain = @import("RTerrain.zig");
const rtrigger = @import("RTrigger.zig");

const st = @import("../util/active_state.zig");
const ActiveState = st.ActiveState;
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
const TestFlags1 = re.Test.TEST_FLAGS1;
const rt = @import("racer").Text;
const rto = rt.TextStyleOpts;

const w32 = @import("zigwin32");
const POINT = w32.foundation.POINT;
const GetAsyncKeyState = w32.ui.input.keyboard_and_mouse.GetAsyncKeyState;
const GetForegroundWindow = w32.ui.windows_and_messaging.GetForegroundWindow;
const VK_SHIFT = w32.ui.input.keyboard_and_mouse.VK_SHIFT;
const KS_DOWN: i16 = -1;
const KS_PRESSED: i16 = 1; // since last call

// NOTE: may want to figure out all the code caves in .data for potential use
// TODO: split up the versioning, global structs, etc. from the business logic

// STATE

pub var GLOBAL_STATE: GlobalState = .{};

fn global_player_reset(self: *GlobalState) void {
    const p = &self.player;

    p.boosting = .Off;
    p.underheating = .On; // you start the race underheating
    p.overheating = .Off;
    p.dead = .Off;
    p.deaths = 0;
}

fn global_player_update(self: *GlobalState) void {
    const p = &self.player;
    const pt = re.Test.GetPlayerAssertValid();

    p.boosting.update(pt.flags1.IS_BOOSTING);
    p.underheating.update(re.Test.GetUnderheating(pt));
    p.overheating.update(re.Test.GetOverheating(pt));
    p.dead.update(pt.flags1.IS_DEAD);
    if (p.dead == .JustOn) p.deaths += 1;
}

fn SInitLatePassed() callconv(.C) bool {
    return GLOBAL_STATE.init_late_passed;
} // init_late_passed

fn SPracticeMode() callconv(.C) bool {
    return GLOBAL_STATE.practice_mode;
} // practice_mode

fn SWindowInForeground() callconv(.C) bool {
    return GLOBAL_STATE.window_in_foreground;
} // window_in_foreground

fn SFPSAvg() callconv(.C) f32 {
    return GLOBAL_STATE.fps_avg;
} // fps_avg

fn SInRace() callconv(.C) ActiveState {
    return GLOBAL_STATE.in_race;
} // in_race

fn SRaceState() callconv(.C) RaceState {
    return GLOBAL_STATE.race_state;
} // race_state

fn SRaceStatePrev() callconv(.C) RaceState {
    return GLOBAL_STATE.race_state_prev;
} // race_state_prev

fn SRaceStateNew() callconv(.C) bool {
    return GLOBAL_STATE.race_state_new;
} // race_state_new

fn SPlayerBoosting() callconv(.C) ActiveState {
    return GLOBAL_STATE.player.boosting;
} // player -> boosting

fn SPlayerUnderheating() callconv(.C) ActiveState {
    return GLOBAL_STATE.player.underheating;
} // player -> underheating

fn SPlayerOverheating() callconv(.C) ActiveState {
    return GLOBAL_STATE.player.overheating;
} // player -> overheating

fn SPlayerDead() callconv(.C) ActiveState {
    return GLOBAL_STATE.player.dead;
} // player -> dead

fn SPlayerDeaths() callconv(.C) u32 {
    return GLOBAL_STATE.player.deaths;
} // player -> deaths

// GLOBAL FUNCTIONS

pub var GLOBAL_FUNCTION: GlobalFunction = .{
    // Settings
    .ASettingSave = &asettings.ASave,
    .ASettingSaveAuto = &asettings.ASaveAuto,
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
    // State
    .SInitLatePassed = &SInitLatePassed,
    .SPracticeMode = &SPracticeMode,
    .SWindowInForeground = &SWindowInForeground,
    .SFPSAvg = &SFPSAvg,
    .SInRace = &SInRace,
    .SRaceState = &SRaceState,
    .SRaceStatePrev = &SRaceStatePrev,
    .SRaceStateNew = &SRaceStateNew,
    .SPlayerBoosting = &SPlayerBoosting,
    .SPlayerUnderheating = &SPlayerUnderheating,
    .SPlayerOverheating = &SPlayerOverheating,
    .SPlayerDead = &SPlayerDead,
    .SPlayerDeaths = &SPlayerDeaths,
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
    const kb_shift: i16 = GetAsyncKeyState(@intFromEnum(VK_SHIFT));
    const kb_shift_dn: bool = (kb_shift & KS_DOWN) != 0;
    if (kb_shift_dn)
        return false;

    return true;
}

// HOOK CALLS

pub fn OnInit(_: *GlobalFunction) callconv(.C) void {}

pub fn OnInitLate(_: *GlobalFunction) callconv(.C) void {
    GLOBAL_STATE.init_late_passed = true;
}

pub fn OnDeinit(_: *GlobalFunction) callconv(.C) void {}

pub fn EarlyEngineUpdateB(_: *GlobalFunction) callconv(.C) void {
    const hwnd_racer: u32 = @intFromPtr(rg.WINDOW_HWND.*);
    const hwnd_fg: u32 = if (GetForegroundWindow()) |h| @intFromPtr(h) else 0;
    GLOBAL_STATE.window_in_foreground = hwnd_racer == hwnd_fg;
}

pub fn EngineUpdateStage14A(_: *GlobalFunction) callconv(.C) void {
    const player_ready: bool = rrd.pPlayer.* != null and rrd.pPlayer.*.?.pTestEntity != null;
    GLOBAL_STATE.in_race.update(player_ready);

    // FIXME: use jdge flags
    GLOBAL_STATE.race_state_prev = GLOBAL_STATE.race_state;
    GLOBAL_STATE.race_state = blk: {
        if (!GLOBAL_STATE.in_race.on()) break :blk .None;
        if (rg.IN_RACE.* == 0) break :blk .PreRace; // i.e. in race scene?
        // TODO: figure out how the engine knows to set these and use those instead
        const flags1 = re.Test.pPlayer.*.?.flags1;
        if (flags1.IN_COUNTDOWN) break :blk .Countdown;
        const postrace: bool = !flags1.RACE_NOT_ENDED;
        const show_stats: bool = re.Manager.entity(.Jdge, 0).Flags.RACE_STATE == .PostRace;
        if (postrace and show_stats) break :blk .PostRace;
        if (postrace) break :blk .PostRaceExiting;
        break :blk .Racing;
    };
    GLOBAL_STATE.race_state_new = GLOBAL_STATE.race_state != GLOBAL_STATE.race_state_prev;

    if (GLOBAL_STATE.race_state_new and GLOBAL_STATE.race_state == .PreRace) global_player_reset(&GLOBAL_STATE);
    if (GLOBAL_STATE.in_race.on()) global_player_update(&GLOBAL_STATE);
}

pub fn TimerUpdateA(_: *GlobalFunction) callconv(.C) void {
    const fps_res: f32 = 1 / rti.FRAMETIME.* * 2;
    GLOBAL_STATE.fps_avg = (GLOBAL_STATE.fps_avg * (fps_res - 1) + (1 / rti.FRAMETIME.*)) / fps_res;
}

pub fn MenuTitleScreenB(_: *GlobalFunction) callconv(.C) void {
    // TODO: make text only appear on the actual title screen, i.e. remove from file select etc.
    DrawVersionString();
    DrawMenuPracticeModeLabel();
}

pub fn MenuStartRaceB(_: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuRaceResultsB(_: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuTrackSelectB(_: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuTrackB(_: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}
