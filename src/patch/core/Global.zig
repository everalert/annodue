const Self = @This();

const GlobalState = @import("SharedDef.zig").GlobalState;
const GlobalFunction = @import("SharedDef.zig").GlobalFunction;
const RaceState = @import("SharedDef.zig").RaceState;

const std = @import("std");
const win = std.os.windows;

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
const w32kb = w32.ui.input.keyboard_and_mouse;
const w32xc = w32.ui.input.xbox_controller;
const w32wm = w32.ui.windows_and_messaging;
const POINT = w32.foundation.POINT;
const KS_DOWN: i16 = -1;
const KS_PRESSED: i16 = 1; // since last call

// NOTE: may want to figure out all the code caves in .data for potential use
// TODO: split up the versioning, global structs, etc. from the business logic

// STATE

pub var GLOBAL_STATE: GlobalState = .{};

fn global_player_reset(self: *GlobalState) void {
    const p = &self.player;
    p.upgrades_lv = rrd.PLAYER.*.pFile.upgrade_lv; // TODO: remove from gs, now that it's easy?
    p.upgrades_hp = rrd.PLAYER.*.pFile.upgrade_hp; // TODO: remove from gs, now that it's easy?
    p.upgrades = for (0..7) |i| {
        if (p.upgrades_lv[i] > 0 and p.upgrades_hp[i] > 0) break true;
    } else false;

    p.flags1 = std.mem.zeroInit(re.Test.TEST_FLAGS1, .{});
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

    p.boosting.update(p.flags1.IS_BOOSTING);
    p.underheating.update(p.heat >= 100);
    p.overheating.update(for (0..6) |i| {
        if (engine[i] & (1 << 3) > 0) break true;
    } else false);
    p.dead.update(p.flags1.IS_DEAD);
    if (p.dead == .JustOn) p.deaths += 1;
}

fn SPatchMemory() callconv(.C) [*]u8 {
    return GLOBAL_STATE.patch_memory;
} // patch_memory

fn SPatchSize() callconv(.C) u32 {
    return GLOBAL_STATE.patch_size;
} // patch_size

fn SPatchOffset() callconv(.C) u32 {
    return GLOBAL_STATE.patch_offset;
} // patch_offset, WARN: some funcs write to this

fn SInitLatePassed() callconv(.C) bool {
    return GLOBAL_STATE.init_late_passed;
} // init_late_passed

fn SPracticeMode() callconv(.C) bool {
    return GLOBAL_STATE.practice_mode;
} // practice_mode

fn SWindowInForeground() callconv(.C) bool {
    return GLOBAL_STATE.window_in_foreground;
} // window_in_foreground

fn SDt() callconv(.C) f32 {
    return GLOBAL_STATE.dt_f;
} // dt_f

fn SFPS() callconv(.C) f32 {
    return GLOBAL_STATE.fps;
} // fps

fn SFPSAvg() callconv(.C) f32 {
    return GLOBAL_STATE.fps_avg;
} // fps_avg

fn STimestamp() callconv(.C) u32 {
    return GLOBAL_STATE.timestamp;
} // timestamp

fn SFrameCount() callconv(.C) u32 {
    return GLOBAL_STATE.framecount;
} // frame_count

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

fn SPlayerUpgrades() callconv(.C) bool {
    return GLOBAL_STATE.player.upgrades;
} // player -> upgrades

// FIXME: crashes when included in global fn
fn SPlayerUpgradesLv(out: [*]u8) callconv(.C) void {
    _ = out;
    //@memcpy(@as(*[7]u8, @ptrCast(out)), &GLOBAL_STATE.player.upgrades_lv);
} // 7-byte array; player -> upgrades_lv

// FIXME: crashes when included in global fn
fn SPlayerUpgradesHP(out: [*]u8) callconv(.C) void {
    @memcpy(@as(*[7]u8, @ptrCast(out)), &GLOBAL_STATE.player.upgrades_hp);
} // 7-byte array; player -> upgrades_hp

fn SPlayerFlags1() callconv(.C) TestFlags1 {
    return GLOBAL_STATE.player.flags1;
} // player -> flags1

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

fn SPlayerHeatRate() callconv(.C) f32 {
    return GLOBAL_STATE.player.heat_rate;
} // player -> heat_rate

fn SPlayerCoolRate() callconv(.C) f32 {
    return GLOBAL_STATE.player.cool_rate;
} // player -> cool_rate

fn SPlayerHeat() callconv(.C) f32 {
    return GLOBAL_STATE.player.heat;
} // player -> heat

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
    .SPatchMemory = &SPatchMemory,
    .SPatchSize = &SPatchSize,
    .SPatchOffset = &SPatchOffset,
    .SInitLatePassed = &SInitLatePassed,
    .SPracticeMode = &SPracticeMode,
    .SWindowInForeground = &SWindowInForeground,
    .SDt = &SDt,
    .SFPS = &SFPS,
    .SFPSAvg = &SFPSAvg,
    .STimestamp = &STimestamp,
    .SFrameCount = &SFrameCount,
    .SInRace = &SInRace,
    .SRaceState = &SRaceState,
    .SRaceStatePrev = &SRaceStatePrev,
    .SRaceStateNew = &SRaceStateNew,
    .SPlayerUpgrades = &SPlayerUpgrades,
    //.SPlayerUpgradesLv = &SPlayerUpgradesLv,
    //.SPlayerUpgradesHP = &SPlayerUpgradesHP,
    .SPlayerFlags1 = &SPlayerFlags1,
    .SPlayerBoosting = &SPlayerBoosting,
    .SPlayerUnderheating = &SPlayerUnderheating,
    .SPlayerOverheating = &SPlayerOverheating,
    .SPlayerDead = &SPlayerDead,
    .SPlayerDeaths = &SPlayerDeaths,
    .SPlayerHeatRate = &SPlayerHeatRate,
    .SPlayerCoolRate = &SPlayerCoolRate,
    .SPlayerHeat = &SPlayerHeat,
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
    const hwnd_fg: u32 = if (w32wm.GetForegroundWindow()) |h| @intFromPtr(h) else 0;
    GLOBAL_STATE.window_in_foreground = hwnd_racer == hwnd_fg;
}

pub fn EngineUpdateStage14A(_: *GlobalFunction) callconv(.C) void {
    const player_ready: bool = rrd.PLAYER_PTR.* != 0 and rrd.PLAYER.*.pTestEntity != 0;
    GLOBAL_STATE.in_race.update(player_ready);

    // FIXME: use jdge flags
    GLOBAL_STATE.race_state_prev = GLOBAL_STATE.race_state;
    GLOBAL_STATE.race_state = blk: {
        if (!GLOBAL_STATE.in_race.on()) break :blk .None;
        if (rg.IN_RACE.* == 0) break :blk .PreRace; // i.e. in race scene?
        // TODO: figure out how the engine knows to set these and use those instead
        const flags1 = re.Test.PLAYER.*.flags1;
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
    GLOBAL_STATE.dt_f = rti.FRAMETIME.*;
    GLOBAL_STATE.fps = rti.FPS.*;
    const fps_res: f32 = 1 / GLOBAL_STATE.dt_f * 2;
    GLOBAL_STATE.fps_avg = (GLOBAL_STATE.fps_avg * (fps_res - 1) + (1 / GLOBAL_STATE.dt_f)) / fps_res;
    GLOBAL_STATE.timestamp = rti.TIMESTAMP.*;
    GLOBAL_STATE.framecount = rti.FRAMECOUNT.*;
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
