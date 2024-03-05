const Self = @This();

const std = @import("std");

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;
const w32wm = w32.ui.windows_and_messaging;
const POINT = w32.foundation.POINT;
const RECT = w32.foundation.RECT;
const HWND = w32.foundation.HWND;

const xinput = @import("xinput.zig");
const st = @import("active_state.zig");

const global = @import("../global.zig");
const GlobalState = global.GlobalState;
const GlobalFn = global.GlobalFn;

pub const INPUT_DOWN: u8 = 0b01;
pub const INPUT_NEW: u8 = 0b10;

pub const INPUT_XINPUT = extern struct {
    Button: [std.enums.values(XINPUT_GAMEPAD_BUTTON_INDEX).len]st.ActiveState,
    Axis: [std.enums.values(XINPUT_GAMEPAD_AXIS_INDEX).len]f32,
};

pub const INPUT_MOUSE = extern struct {
    raw: POINT,
    raw_d: POINT,
    window: POINT,
    window_d: POINT,
    window_in: st.ActiveState,
};

const state = extern struct {
    var kb: [256]u8 = std.mem.zeroes([256]u8);
    var mouse: INPUT_MOUSE = std.mem.zeroInit(INPUT_MOUSE, .{});
    var xbox_raw: xinput.XINPUT_GAMEPAD = std.mem.zeroInit(xinput.XINPUT_GAMEPAD, .{});
    var xbox: INPUT_XINPUT = std.mem.zeroInit(INPUT_XINPUT, .{});
};

pub fn update(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gs;
    _ = gv;
    _ = initialized;
    update_xinput();
    update_kb();
    //update_mouse(@ptrCast(gs.hwnd));
}

// XINPUT GAMEPAD

pub const XINPUT_GAMEPAD_AXIS_INDEX = enum(u16) {
    TriggerL,
    TriggerR,
    StickLX,
    StickLY,
    StickRX,
    StickRY,
};

pub const XINPUT_GAMEPAD_BUTTON_INDEX = enum(u16) {
    DPAD_UP,
    DPAD_DOWN,
    DPAD_LEFT,
    DPAD_RIGHT,
    START,
    BACK,
    LEFT_THUMB,
    RIGHT_THUMB,
    LEFT_SHOULDER,
    RIGHT_SHOULDER,
    A,
    B,
    X,
    Y,
};

pub fn update_xinput() callconv(.C) void {
    const controller: u8 = 0;
    var new_state = std.mem.zeroInit(xinput.XINPUT_STATE, .{});
    if (xinput.XInputGetState(controller, &new_state) == 0) {
        state.xbox_raw = new_state.Gamepad;
        const buttons = comptime std.enums.values(xinput.XINPUT_GAMEPAD_BUTTON);
        for (buttons, 0..) |b, i| {
            const b_int: u16 = @intFromEnum(b);
            state.xbox.Button[i].update((new_state.Gamepad.wButtons & b_int) > 0);
        }
        state.xbox.Axis[0] = @as(f32, @floatFromInt(new_state.Gamepad.bLeftTrigger)) / 255;
        state.xbox.Axis[1] = @as(f32, @floatFromInt(new_state.Gamepad.bRightTrigger)) / 255;
        state.xbox.Axis[2] = @as(f32, @floatFromInt(new_state.Gamepad.sThumbLX)) / 32767;
        state.xbox.Axis[3] = @as(f32, @floatFromInt(new_state.Gamepad.sThumbLY)) / 32767;
        state.xbox.Axis[4] = @as(f32, @floatFromInt(new_state.Gamepad.sThumbRX)) / 32767;
        state.xbox.Axis[5] = @as(f32, @floatFromInt(new_state.Gamepad.sThumbRY)) / 32767;
    } else {
        state.xbox_raw = std.mem.zeroInit(xinput.XINPUT_GAMEPAD, .{});
    }
}

pub fn get_xinput_button(button: XINPUT_GAMEPAD_BUTTON_INDEX) st.ActiveState {
    return state.xbox.Button[@intFromEnum(button)];
}

pub fn get_xinput_axis(axis: XINPUT_GAMEPAD_AXIS_INDEX) f32 {
    return state.xbox.Axis[@intFromEnum(axis)];
}

// KEYBOARD

pub fn update_kb() callconv(.C) void {
    var kb_new: [256]u8 = undefined;
    _ = w32kb.GetKeyboardState(&kb_new);
    for (kb_new, 0..) |k, i| {
        const down: u8 = k >> 7; // KB_DOWN
        const new: u8 = (down ^ state.kb[i] & 0x01) << 1; // KB_NEW
        state.kb[i] = down | new;
    }
}

pub fn get_kb(keycode: w32kb.VIRTUAL_KEY, down: bool, new: bool) bool {
    const key: u8 = state.kb[@as(u8, @truncate(@intFromEnum(keycode)))];
    return ((key & INPUT_DOWN) > 0) == down and ((key & INPUT_NEW) > 0) == new;
}

pub fn get_kb_down(keycode: w32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, true, false);
}

pub fn get_kb_up(keycode: w32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, false, false);
}

pub fn get_kb_pressed(keycode: w32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, true, true);
}

pub fn get_kb_released(keycode: w32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, false, true);
}

// MOUSE

// FIXME: this code worked properly at one point, but now behaves like the normal
// game cursor. maybe it only worked because of dgvoodoo forcing a resize after tab-out?
pub fn update_mouse(hwnd: HWND) callconv(.C) void {
    var m: POINT = undefined;
    var c: RECT = undefined;
    if (w32wm.GetCursorPos(&m) > 0 and w32wm.GetClientRect(hwnd, &c) > 0) {
        const s: *INPUT_MOUSE = &state.mouse;

        s.raw_d.x = m.x - s.raw.x;
        s.raw_d.y = m.y - s.raw.y;
        s.raw = m;

        const x_scale: f32 = 640 / @as(f32, @floatFromInt(c.right - c.left));
        const y_scale: f32 = 480 / @as(f32, @floatFromInt(c.bottom - c.top));
        const wx: i16 = @intFromFloat(@as(f32, @floatFromInt(m.x - c.left)) * x_scale);
        const wy: i16 = @intFromFloat(@as(f32, @floatFromInt(m.y - c.top)) * y_scale);
        s.window_d.x = wx - s.window.x;
        s.window_d.y = wy - s.window.y;
        s.window.x = wx;
        s.window.y = wy;
        s.window_in.update(wx >= 0 and wx < 640 and wy >= 0 and wy < 480);
    } else {
        state.mouse = std.mem.zeroInit(INPUT_MOUSE, .{});
    }
}

pub fn get_mouse_raw() callconv(.C) POINT {
    return state.mouse.raw;
}

pub fn get_mouse_raw_d() callconv(.C) POINT {
    return state.mouse.raw_d;
}

pub fn get_mouse_window() callconv(.C) POINT {
    return state.mouse.window;
}

pub fn get_mouse_window_d() callconv(.C) POINT {
    return state.mouse.window_d;
}

pub fn get_mouse_inside() callconv(.C) st.ActiveState {
    return state.mouse.window_in;
}
