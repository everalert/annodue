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

// TODO: move all the common game check stuff from plugins/modules to here; cleanup
pub const state = struct {
    pub var initialized_late: bool = false;
    pub var practice_mode: bool = false;

    pub var hwnd: ?HWND = null;
    pub var hinstance: ?HINSTANCE = null;

    pub var in_race: bool = false;
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

pub fn GameLoop_Before() void {
    state.in_race = mem.read(rc.ADDR_IN_RACE, u8) > 0;

    if (input.get_kb_pressed(.P) and (!(state.in_race and state.practice_mode)))
        state.practice_mode = !state.practice_mode;
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
