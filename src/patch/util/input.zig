const Self = @This();

const std = @import("std");
const win32 = @import("../import/import.zig").win32;
const win32kb = win32.ui.input.keyboard_and_mouse;

pub const INPUT_DOWN: u8 = 0b01;
pub const INPUT_NEW: u8 = 0b10;

const state = struct {
    var kb_new: [256]u8 = undefined;
    var kb: [256]u8 = std.mem.zeroes([256]u8);
};

pub fn update_kb() void {
    _ = win32kb.GetKeyboardState(&state.kb_new);
    for (state.kb_new, 0..) |k, i| {
        const down: u8 = k >> 7; // KB_DOWN
        const new: u8 = (down ^ state.kb[i] & 0x01) << 1; // KB_NEW
        state.kb[i] = down | new;
    }
}

pub fn get_kb(keycode: u8, down: bool, new: bool) bool {
    return ((state.kb[keycode] & INPUT_DOWN) > 0) == down and
        ((state.kb[keycode] & INPUT_NEW) > 0) == new;
}
