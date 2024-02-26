const Self = @This();

const std = @import("std");
const win32 = @import("zigwin32");
const win32kb = win32.ui.input.keyboard_and_mouse;

const global = @import("../global.zig");
const GlobalState = global.GlobalState;
const GlobalFn = global.GlobalFn;

pub const INPUT_DOWN: u8 = 0b01;
pub const INPUT_NEW: u8 = 0b10;

const state = struct {
    var kb_new: [256]u8 = undefined;
    var kb: [256]u8 = std.mem.zeroes([256]u8);
};

pub fn update_kb(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    _ = win32kb.GetKeyboardState(&state.kb_new);
    for (state.kb_new, 0..) |k, i| {
        const down: u8 = k >> 7; // KB_DOWN
        const new: u8 = (down ^ state.kb[i] & 0x01) << 1; // KB_NEW
        state.kb[i] = down | new;
    }
}

pub fn get_kb(keycode: win32kb.VIRTUAL_KEY, down: bool, new: bool) bool {
    const key: u8 = state.kb[@as(u8, @truncate(@intFromEnum(keycode)))];
    return ((key & INPUT_DOWN) > 0) == down and ((key & INPUT_NEW) > 0) == new;
}

pub fn get_kb_down(keycode: win32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, true, false);
}

pub fn get_kb_up(keycode: win32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, false, false);
}

pub fn get_kb_pressed(keycode: win32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, true, true);
}

pub fn get_kb_released(keycode: win32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, false, true);
}
