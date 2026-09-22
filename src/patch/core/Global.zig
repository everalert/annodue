const Self = @This();

const GlobalState = @import("SharedDef.zig").GlobalState;
const GlobalFunction = @import("SharedDef.zig").GlobalFunction;
const RaceState = @import("SharedDef.zig").RaceState;
const HangState = @import("SharedDef.zig").HangState;

const std = @import("std");

const GDraw = @import("GDraw.zig");
const GFreeze = @import("GFreeze.zig");
const GHideRaceUI = @import("GHideRaceUI.zig");
const toast = @import("Toast.zig");
const AInput = @import("AInput.zig");
const ASettings = @import("ASettings.zig");
const AMemory = @import("AMemory.zig");
const RTerrain = @import("RTerrain.zig");
const RTrigger = @import("RTrigger.zig");
const RAddress = @import("RAddress.zig");

const st = @import("../util/toggle_state.zig");
const ToggleState = st.ToggleState;

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
    const pt = re.Test.GetPlayerAssertValid(); // NOTE: indirect game image read

    p.boosting.update(pt.flags1.IS_BOOSTING);
    p.boost_charging.update(pt.boostChargeStatus == 1);
    p.boost_ready.update(pt.boostChargeStatus == 2);
    p.underheating.update(re.Test.GetUnderheating(pt)); // NOTE: indirect game image read
    p.overheating.update(re.Test.GetOverheating(pt)); // NOTE: indirect game image read
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

fn SInRace() callconv(.C) ToggleState {
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

fn SHangState() callconv(.C) HangState {
    return GLOBAL_STATE.hang_state;
} // hang_state

fn SHangStatePrev() callconv(.C) HangState {
    return GLOBAL_STATE.hang_state_prev;
} // hang_state_prev

fn SHangStateNew() callconv(.C) bool {
    return GLOBAL_STATE.hang_state_new;
} // hang_state_new

fn SPlayerBoostCharging() callconv(.C) ToggleState {
    return GLOBAL_STATE.player.boost_charging;
} // player -> boost_charging

fn SPlayerBoostReady() callconv(.C) ToggleState {
    return GLOBAL_STATE.player.boost_ready;
} // player -> boost_ready

fn SPlayerBoosting() callconv(.C) ToggleState {
    return GLOBAL_STATE.player.boosting;
} // player -> boosting

fn SPlayerUnderheating() callconv(.C) ToggleState {
    return GLOBAL_STATE.player.underheating;
} // player -> underheating

fn SPlayerOverheating() callconv(.C) ToggleState {
    return GLOBAL_STATE.player.overheating;
} // player -> overheating

fn SPlayerDead() callconv(.C) ToggleState {
    return GLOBAL_STATE.player.dead;
} // player -> dead

fn SPlayerDeaths() callconv(.C) u32 {
    return GLOBAL_STATE.player.deaths;
} // player -> deaths

// GLOBAL FUNCTIONS

pub var GLOBAL_FUNCTION: GlobalFunction = .{
    // Memory
    .AMemoryGetPermanent = &AMemory.AMemoryGetPermanent,
    .AMemoryGetPermanentZero = &AMemory.AMemoryGetPermanentZero,
    .AMemoryGetTemporary = &AMemory.AMemoryGetTemporary,
    .AMemoryGetTemporaryZero = &AMemory.AMemoryGetTemporaryZero,
    // Settings
    .ASettingSave = &ASettings.ASettingSave,
    .ASettingSaveAuto = &ASettings.ASettingSaveAuto,
    .ASettingOccupy = &ASettings.ASettingOccupy,
    .ASettingVacate = &ASettings.ASettingVacate,
    .ASettingVacateAll = &ASettings.ASettingVacateAll,
    .ASettingUpdate = &ASettings.ASettingUpdate,
    .ASettingResetAllDefault = &ASettings.ASettingResetAllDefault,
    .ASettingResetAllFile = &ASettings.ASettingResetAllFile,
    .ASettingCleanAll = &ASettings.ASettingCleanAll,
    .ASettingSectionOccupy = &ASettings.ASettingSectionOccupy,
    .ASettingSectionVacate = &ASettings.ASettingSectionVacate,
    .ASettingSectionRunUpdate = &ASettings.ASettingSectionRunUpdate,
    .ASettingSectionResetDefault = &ASettings.ASettingSectionResetDefault,
    .ASettingSectionResetFile = &ASettings.ASettingSectionResetFile,
    .ASettingSectionClean = &ASettings.ASettingSectionClean,
    // Input
    .AInputKbGet = AInput.AInputKbGet,
    .AInputKbGetRaw = AInput.AInputKbGetRaw,
    .AInputMouseGet = AInput.AInputMouseGet,
    .AInputMouseGetDelta = AInput.AInputMouseGetDelta,
    .AInputMouseLock = AInput.AInputMouseLock,
    //.AInputMouseIsInWindow=AInput.AInputMouseIsInWindow,
    .AInputXInputGetButton = AInput.AInputXInputGetButton,
    .AInputXInputGetAxis = AInput.AInputXInputGetAxis,
    // Game
    .GDrawText = &GDraw.GDrawText,
    //.GDrawTextBox = &draw.GDrawTextBox,
    .GDrawRect = &GDraw.GDrawRect,
    .GDrawRectBdr = &GDraw.GDrawRectBdr,
    .GFreezeOn = &GFreeze.GFreezeOn,
    .GFreezeOff = &GFreeze.GFreezeOff,
    .GFreezeIsOn = &GFreeze.GFreezeIsOn,
    .GHideRaceUIOn = &GHideRaceUI.GHideRaceUIOn,
    .GHideRaceUIOff = &GHideRaceUI.GHideRaceUIOff,
    .GHideRaceUIIsOn = &GHideRaceUI.GHideRaceUIIsOn,
    // Toast
    .ToastNew = &toast.ToastSystem.NewToast,
    // Resources
    .RAddressRangeAvailable = &RAddress.RAddressRangeAvailable,
    .RAddressRangeReserve = &RAddress.RAddressRangeReserve,
    .RAddressRangeRelease = &RAddress.RAddressRangeRelease,
    .RAddressRangeRestore = &RAddress.RAddressRangeRestore,
    .RAddressRangeRead = &RAddress.RAddressRangeRead,
    .RAddressRangeWriteSt = &RAddress.RAddressRangeWriteSt,
    .RAddressRangeWriteEd = &RAddress.RAddressRangeWriteEd,
    .RAddressRangeContainsRange = &RAddress.RAddressRangeContainsRange,
    .RAddressRangeSetFlagRestoreOnRelease = &RAddress.RAddressRangeSetFlagRestoreOnRelease,
    .RTerrainRequest = &RTerrain.RRequest,
    .RTerrainRelease = &RTerrain.RRelease,
    .RTerrainReleaseAll = &RTerrain.RReleaseAll,
    .RTriggerRequest = &RTrigger.RRequest,
    .RTriggerRelease = &RTrigger.RRelease,
    .RTriggerReleaseAll = &RTrigger.RReleaseAll,
    // State
    .SInitLatePassed = &SInitLatePassed,
    .SPracticeMode = &SPracticeMode,
    .SWindowInForeground = &SWindowInForeground,
    .SFPSAvg = &SFPSAvg,
    .SInRace = &SInRace,
    .SRaceState = &SRaceState,
    .SRaceStatePrev = &SRaceStatePrev,
    .SRaceStateNew = &SRaceStateNew,
    .SHangState = &SHangState,
    .SHangStatePrev = &SHangStatePrev,
    .SHangStateNew = &SHangStateNew,
    .SPlayerBoosting = &SPlayerBoosting,
    .SPlayerBoostCharging = &SPlayerBoostCharging,
    .SPlayerBoostReady = &SPlayerBoostReady,
    .SPlayerUnderheating = &SPlayerUnderheating,
    .SPlayerOverheating = &SPlayerOverheating,
    .SPlayerDead = &SPlayerDead,
    .SPlayerDeaths = &SPlayerDeaths,
};

// UTIL

const style_practice_label = rt.hMakeTextHeadStyle(.Default, true, .Yellow, .Right, .{rto.ToggleShadow}) catch "";

fn DrawMenuPracticeModeLabel(gf: *GlobalFunction) void {
    _ = gf.GDrawText(.SystemP, rt.hMakeText(640 - 20, 16, "Practice Mode", .{}, 0xFFFFFFFF, style_practice_label) catch null);
}

fn DrawVersionString(gf: *GlobalFunction) void {
    _ = gf.GDrawText(.System, rt.hMakeText(36, 480 - 24, "{s}", .{VERSION_STR}, 0xFFFFFFFF, null) catch null);
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
    GLOBAL_STATE.hang_state_prev = GLOBAL_STATE.hang_state;
    if (GLOBAL_STATE.in_race.on()) {
        GLOBAL_STATE.hang_state = .None;
        GLOBAL_STATE.race_state = blk: {
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
    } else {
        GLOBAL_STATE.race_state = .None;
        const hang = re.Manager.entity(.Hang, 0);
        GLOBAL_STATE.hang_state = hang.MenuScreen;
    }
    GLOBAL_STATE.race_state_new = GLOBAL_STATE.race_state != GLOBAL_STATE.race_state_prev;
    GLOBAL_STATE.hang_state_new = GLOBAL_STATE.hang_state != GLOBAL_STATE.hang_state_prev;

    if (GLOBAL_STATE.race_state_new and GLOBAL_STATE.race_state == .PreRace) global_player_reset(&GLOBAL_STATE);
    if (GLOBAL_STATE.in_race.on()) global_player_update(&GLOBAL_STATE);
}

pub fn TimerUpdateA(_: *GlobalFunction) callconv(.C) void {
    // framerate-independent lerp (damp function/exponential decay)
    const RAW_FPS: f32 = 1 / rti.FRAMETIME.*;
    const DECAY_FACTOR: f32 = 0.05;
    GLOBAL_STATE.fps_avg = std.math.lerp(
        GLOBAL_STATE.fps_avg,
        RAW_FPS,
        @as(f32, 1) - std.math.pow(f32, DECAY_FACTOR, rti.FRAMETIME.*),
    );
}

pub fn MenuTitleScreenB(gf: *GlobalFunction) callconv(.C) void {
    // TODO: make text only appear on the actual title screen, i.e. remove from file select etc.
    DrawVersionString(gf);
    DrawMenuPracticeModeLabel(gf);
}

pub fn MenuStartRaceB(gf: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel(gf);
}

pub fn MenuRaceResultsB(gf: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel(gf);
}

pub fn MenuTrackSelectB(gf: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel(gf);
}

pub fn MenuTrackB(gf: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel(gf);
}
