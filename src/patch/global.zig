const Self = @This();

const std = @import("std");
const HINSTANCE = std.os.windows.HINSTANCE;
const HWND = std.os.windows.HWND;

const settings = @import("settings.zig");
const s = settings.state;

const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");

const win32 = @import("import/import.zig").win32;
const win32kb = win32.ui.input.keyboard_and_mouse;
const win32wm = win32.ui.windows_and_messaging;
const KS_DOWN: i16 = -1;
const KS_PRESSED: i16 = 1; // since last call

// VERSION

const VersionTag = enum(u32) {
    None,
    Alpha,
    Beta,
    ReleaseCandidate,
};

pub const Version = struct {
    pub const major: u32 = 0;
    pub const minor: u32 = 0;
    pub const patch: u32 = 1;
    pub const tag_type: VersionTag = .None;
    pub const tag_no: u32 = 0;
    pub const build: u32 = 76; // based on git commits
};

// STATE

// TODO: move all the common game check stuff from plugins/modules to here; cleanup
pub const state = struct {
    pub var initialized_late: bool = false;
    pub var practice_mode: bool = false;

    pub var hwnd: ?HWND = null;
    pub var hinstance: ?HINSTANCE = null;

    pub var dt_f: f32 = 0;
    pub var fps: f32 = 0;
    pub var fps_avg: f32 = 0;

    pub var in_race: bool = false;
    pub var was_in_race: bool = false;

    // FIXME: probably want to make this request-based, to prevent plugins from
    // clashing with eachother
    // FIXME: also probably need to start thinking about making a distinction
    // between global state and game manipulation functions
    // TODO: turn off race HUD when freezing
    pub const Freeze = struct {
        const pausebit: u32 = 1 << 28;
        var frozen: bool = false;
        var saved_pausebit: usize = undefined;
        var saved_pausepage: u8 = undefined;
        var saved_pausestate: u8 = undefined;
        var saved_pausescroll: f32 = undefined;

        pub fn freeze() void {
            if (frozen) return;
            const pauseflags = r.ReadEntityValue(.Jdge, 0, 0x04, u32);

            saved_pausebit = pauseflags & pausebit;
            saved_pausepage = mem.read(rc.ADDR_PAUSE_PAGE, u8);
            saved_pausestate = mem.read(rc.ADDR_PAUSE_STATE, u8);
            saved_pausescroll = mem.read(rc.ADDR_PAUSE_SCROLLINOUT, f32);

            _ = mem.write(rc.ADDR_PAUSE_PAGE, u8, 2);
            _ = mem.write(rc.ADDR_PAUSE_STATE, u8, 1);
            _ = mem.write(rc.ADDR_PAUSE_SCROLLINOUT, f32, 0);
            _ = r.WriteEntityValue(.Jdge, 0, 0x04, u32, pauseflags & ~pausebit);

            frozen = true;
        }

        pub fn unfreeze() void {
            if (!frozen) return;
            const pauseflags = r.ReadEntityValue(.Jdge, 0, 0x04, u32);

            r.WriteEntityValue(.Jdge, 0, 0x04, u32, pauseflags | saved_pausebit);
            _ = mem.write(rc.ADDR_PAUSE_SCROLLINOUT, f32, saved_pausescroll);
            _ = mem.write(rc.ADDR_PAUSE_STATE, u8, saved_pausestate);
            _ = mem.write(rc.ADDR_PAUSE_PAGE, u8, saved_pausepage);

            frozen = false;
        }
    };
};

// UTIL

fn DrawMenuPracticeModeLabel() void {
    if (state.practice_mode) {
        rf.swrText_CreateEntry1(640 - 20, 16, 255, 255, 255, 255, "~F0~3~s~rPractice Mode");
    }
}

// INIT

pub fn init(alloc: std.mem.Allocator, memory: usize) usize {
    _ = alloc;

    // input-based launch toggles
    const kb_shift: i16 = win32kb.GetAsyncKeyState(@intFromEnum(win32kb.VK_SHIFT));
    const kb_shift_dn: bool = (kb_shift & KS_DOWN) != 0;
    state.practice_mode = kb_shift_dn;

    state.hwnd = mem.read(rc.ADDR_HWND, HWND);
    state.hinstance = mem.read(rc.ADDR_HINSTANCE, HINSTANCE);

    return memory;
}

// HOOK CALLS

pub fn EarlyEngineUpdate_After() void {
    state.was_in_race = state.in_race;
    state.in_race = mem.read(rc.ADDR_IN_RACE, u8) > 0;

    if (input.get_kb_pressed(.P) and (!(state.in_race and state.practice_mode)))
        state.practice_mode = !state.practice_mode;
}

pub fn TimerUpdate_After() void {
    state.dt_f = mem.read(rc.ADDR_TIME_FRAMETIME, f32);
    state.fps = mem.read(rc.ADDR_TIME_FPS, f32);
    const fps_res: f32 = 1 / state.dt_f * 2;
    state.fps_avg = (state.fps_avg * (fps_res - 1) + (1 / state.dt_f)) / fps_res;
}

pub fn MenuTitleScreen_Before() void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuStartRace_Before() void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuRaceResults_Before() void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuTrack_Before() void {
    DrawMenuPracticeModeLabel();
}
