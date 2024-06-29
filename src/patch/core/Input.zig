const Self = @This();

const std = @import("std");

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;
const w32wm = w32.ui.windows_and_messaging;
const POINT = w32.foundation.POINT;
const RECT = w32.foundation.RECT;
const HWND = w32.foundation.HWND;

const xinput = @import("../util/xinput.zig");
const st = @import("../util/active_state.zig");

const app = @import("../appinfo.zig");
const GlobalSt = app.GLOBAL_STATE;
const GlobalFn = app.GLOBAL_FUNCTION;

pub const INPUT_DOWN: u8 = 0b01;
pub const INPUT_NEW: u8 = 0b10;

// FIXME: some stuff in util is still importing this after moving it to core, split
// up stuff here so that util doesn't depend on core an../core/more

const InputState = extern struct {
    var kb: [256]st.ActiveState = std.mem.zeroes([256]st.ActiveState);
    var xbox_raw: xinput.XINPUT_GAMEPAD = std.mem.zeroInit(xinput.XINPUT_GAMEPAD, .{});
    var xbox: INPUT_XINPUT = std.mem.zeroInit(INPUT_XINPUT, .{});
    var mouse: INPUT_MOUSE = std.mem.zeroInit(INPUT_MOUSE, .{});
    var mouse_lock: bool = false;
};

pub fn InputUpdateB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    update_xinput();
    update_kb();
    //update_mouse();
    update_mouse(@ptrCast(gs.hwnd));
}

// MAPPING

// TODO: add 'dominant' field, as a way of communicating which device is 'active'
pub const InputMap = struct {
    ptr: *anyopaque,
    s_val: ?*st.ActiveState = null,
    f_val: ?*f32 = null,
    updateFn: *const fn (ptr: *anyopaque, gf: *GlobalFn) void,

    pub fn update(self: *InputMap, gf: *GlobalFn) void {
        self.updateFn(self.ptr, gf);
    }

    pub fn gets(self: *InputMap) st.ActiveState {
        return if (self.s_val) |v| v.* else .Off;
    }

    pub fn getf(self: *InputMap) f32 {
        return if (self.f_val) |v| v.* else 0;
    }
};

// TODO: StickInputMap, with deadzone inbuilt, and remove kb_scale in lieu of 'dominant' field on InputMap

// TODO: inbuilt deadzone, remove kb_scale in lieu of 'dominant' field on InputMap
pub const AxisInputMap = struct {
    kb_dec: ?w32kb.VIRTUAL_KEY = null,
    kb_inc: ?w32kb.VIRTUAL_KEY = null,
    xi_dec: ?XINPUT_GAMEPAD_AXIS_INDEX = null,
    xi_inc: ?XINPUT_GAMEPAD_AXIS_INDEX = null,
    kb_scale: f32 = 1,
    state: f32 = 0,

    fn update(ptr: *anyopaque, gf: *GlobalFn) void {
        const self: *AxisInputMap = @ptrCast(@alignCast(ptr));

        const kb_dec: f32 = if (self.kb_dec) |k| @floatFromInt(@intFromBool(gf.InputGetKbRaw(k).on())) else 0;
        const kb_inc: f32 = if (self.kb_inc) |k| @floatFromInt(@intFromBool(gf.InputGetKbRaw(k).on())) else 0;
        const xi_dec: f32 = if (self.xi_dec) |x| gf.InputGetXInputAxis(x) else 0;
        const xi_inc: f32 = if (self.xi_inc) |x| gf.InputGetXInputAxis(x) else 0;

        self.state = std.math.clamp(xi_inc - xi_dec + (kb_inc - kb_dec) * self.kb_scale, -1, 1);

        //const kb: f32 = std.math.clamp((kb_inc - kb_dec) * self.kb_scale, -1, 1);
        //const xi: f32 = std.math.clamp(xi_inc - xi_dec, -1, 1);
        //self.state = if (@fabs(kb) > @fabs(xi)) kb else xi;
    }

    pub fn inputMap(self: *AxisInputMap) InputMap {
        return .{
            .ptr = self,
            .f_val = &self.state,
            .updateFn = update,
        };
    }
};

pub const ButtonInputMap = struct {
    kb: ?w32kb.VIRTUAL_KEY = null,
    xi: ?XINPUT_GAMEPAD_BUTTON_INDEX = null,
    state: st.ActiveState = .Off,

    fn update(ptr: *anyopaque, gf: *GlobalFn) void {
        const self: *ButtonInputMap = @ptrCast(@alignCast(ptr));

        const kb: bool = if (self.kb) |k| gf.InputGetKbRaw(k).on() else false;
        const xi: bool = if (self.xi) |x| gf.InputGetXInputButton(x).on() else false;

        self.state.update(kb or xi);
    }

    pub fn inputMap(self: *ButtonInputMap) InputMap {
        return .{
            .ptr = self,
            .s_val = &self.state,
            .updateFn = update,
        };
    }
};

// XINPUT GAMEPAD

pub const INPUT_XINPUT = extern struct {
    Button: [std.enums.values(XINPUT_GAMEPAD_BUTTON_INDEX).len]st.ActiveState,
    Axis: [std.enums.values(XINPUT_GAMEPAD_AXIS_INDEX).len]f32,
};

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

    InputState.xbox_raw = std.mem.zeroInit(xinput.XINPUT_GAMEPAD, .{});
    var new_state: xinput.XINPUT_STATE = undefined;
    if (xinput.XInputGetState(controller, &new_state) == 0)
        InputState.xbox_raw = new_state.Gamepad;

    const buttons = comptime std.enums.values(xinput.XINPUT_GAMEPAD_BUTTON);
    for (buttons, 0..) |b, i| {
        const b_int: u16 = @intFromEnum(b);
        InputState.xbox.Button[i].update((InputState.xbox_raw.wButtons & b_int) > 0);
    }
    InputState.xbox.Axis[0] = @as(f32, @floatFromInt(InputState.xbox_raw.bLeftTrigger)) / 255;
    InputState.xbox.Axis[1] = @as(f32, @floatFromInt(InputState.xbox_raw.bRightTrigger)) / 255;
    InputState.xbox.Axis[2] = @as(f32, @floatFromInt(InputState.xbox_raw.sThumbLX)) / 32767;
    InputState.xbox.Axis[3] = @as(f32, @floatFromInt(InputState.xbox_raw.sThumbLY)) / 32767;
    InputState.xbox.Axis[4] = @as(f32, @floatFromInt(InputState.xbox_raw.sThumbRX)) / 32767;
    InputState.xbox.Axis[5] = @as(f32, @floatFromInt(InputState.xbox_raw.sThumbRY)) / 32767;
}

pub fn get_xinput_button(button: XINPUT_GAMEPAD_BUTTON_INDEX) st.ActiveState {
    return InputState.xbox.Button[@intFromEnum(button)];
}

pub fn get_xinput_axis(axis: XINPUT_GAMEPAD_AXIS_INDEX) f32 {
    return InputState.xbox.Axis[@intFromEnum(axis)];
}

// KEYBOARD

pub fn update_kb() callconv(.C) void {
    const s = extern struct {
        var kb_new: [256]u8 = undefined;
    };
    _ = w32kb.GetKeyboardState(&s.kb_new);

    for (s.kb_new, 0..) |k, i| {
        const down: u8 = k >> 7; // KB_DOWN
        const new: u8 = (down ^ @intFromEnum(InputState.kb[i]) & 0x01) << 1; // KB_NEW
        InputState.kb[i] = @enumFromInt(down | new);
    }
}

pub fn get_kb_raw(keycode: w32kb.VIRTUAL_KEY) st.ActiveState {
    return InputState.kb[@as(u8, @truncate(@intFromEnum(keycode)))];
}

pub fn get_kb(keycode: w32kb.VIRTUAL_KEY, state: st.ActiveState) bool {
    return get_kb_raw(keycode) == state;
}

pub fn get_kb_down(keycode: w32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, .On);
}

pub fn get_kb_up(keycode: w32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, .Off);
}

pub fn get_kb_pressed(keycode: w32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, .JustOn);
}

pub fn get_kb_released(keycode: w32kb.VIRTUAL_KEY) bool {
    return get_kb(keycode, .JustOff);
}

// MOUSE

pub const INPUT_MOUSE = extern struct {
    raw: POINT,
    raw_d: POINT,
    //window: POINT,
    //window_d: POINT,
    //window_in: st.ActiveState,
};

// FIXME: add window-relative coordinates to output in OS units, not 640x480
// old code worked properly at one point, but now behaves like the normal
// game cursor. maybe it only worked because of dgvoodoo forcing a resize after tab-out?
pub fn update_mouse(hwnd: HWND) callconv(.C) void {
    const static = struct {
        var m: POINT = undefined;
        var c: RECT = undefined;
    };

    if (w32wm.GetCursorPos(&static.m) > 0 and w32wm.GetClientRect(hwnd, &static.c) > 0) {
        const s: *INPUT_MOUSE = &InputState.mouse;

        s.raw_d.x = static.m.x - s.raw.x;
        s.raw_d.y = static.m.y - s.raw.y;
        s.raw = static.m;

        // TODO: move mouse lock to state-based system
        // FIXME: game sometimes loses focus when moving mouse left
        // ClipCursor was meant to help but doesn't seem to (fully?) solve the problem
        if (InputState.mouse_lock) {
            InputState.mouse_lock = false;
            s.raw.x = static.c.left + @divTrunc(static.c.right - static.c.left, 2);
            s.raw.y = static.c.top + @divTrunc(static.c.bottom - static.c.top, 2);
            _ = w32wm.SetCursorPos(s.raw.x, s.raw.y);
            //_ = w32wm.ClipCursor(&static.c);
            _ = w32wm.ShowCursor(0);
        }
    } else {
        InputState.mouse = std.mem.zeroInit(INPUT_MOUSE, .{});
    }
}

// for one frame
pub fn lock_mouse() callconv(.C) void {
    InputState.mouse_lock = true;
}

pub fn get_mouse_raw() callconv(.C) POINT {
    return InputState.mouse.raw;
}

pub fn get_mouse_raw_d() callconv(.C) POINT {
    return InputState.mouse.raw_d;
}

//pub fn get_mouse_window() callconv(.C) POINT {
//    return InputState.mouse.window;
//}

//pub fn get_mouse_window_d() callconv(.C) POINT {
//    return InputState.mouse.window_d;
//}

//pub fn get_mouse_inside() callconv(.C) st.ActiveState {
//    return InputState.mouse.window_in;
//}
