const std = @import("std");

const w32 = @import("zigwin32");
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;
const POINT = w32.foundation.POINT;
const RECT = w32.foundation.RECT;
const HWND = w32.foundation.HWND;
const GetKeyboardState = w32.ui.input.keyboard_and_mouse.GetKeyboardState;
const GetCursorPos = w32.ui.windows_and_messaging.GetCursorPos;
const SetCursorPos = w32.ui.windows_and_messaging.SetCursorPos;
const ShowCursor = w32.ui.windows_and_messaging.ShowCursor;
const ClipCursor = w32.ui.windows_and_messaging.ClipCursor;
const GetClientRect = w32.ui.windows_and_messaging.GetClientRect;

const xinput = @import("../xinput.zig");
const XINPUT_GAMEPAD = xinput.XINPUT_GAMEPAD;
const XINPUT_STATE = xinput.XINPUT_STATE;
const XINPUT_GAMEPAD_BUTTON = xinput.XINPUT_GAMEPAD_BUTTON;
const XInputGetState = xinput.XInputGetState;

const ToggleState = @import("../toggle_state.zig").ToggleState;

const rg = @import("racer").Global;

pub const VirtualKey = VIRTUAL_KEY;

const Mouse = extern struct {
    Raw: Point,
    RawDelta: Point,
    //window: Point,
    //window_d: Point,
    //window_in: ToggleState,
};
pub const Point = POINT;

const XInput = extern struct {
    Button: [std.enums.values(XInputButton).len]ToggleState,
    Axis: [std.enums.values(XInputAxis).len]f32,
};
const XInputRaw = XINPUT_GAMEPAD;
const XInputRawState = XINPUT_STATE;
const XInputRawButton = XINPUT_GAMEPAD_BUTTON;
pub const XInputAxis = enum(u16) {
    TriggerL,
    TriggerR,
    StickLX,
    StickLY,
    StickRX,
    StickRY,
};

pub const XInputButton = enum(u16) {
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

// FIXME: some stuff in util is still importing this after moving it to core, split
// up stuff here so that util doesn't depend on core an../core/more

pub const InputState = struct {
    Keyboard: [256]ToggleState,
    Mouse: Mouse,
    bMouseLockNextUpdate: bool,
    XInput: XInput,
    XInputSrc: XInputRaw,

    pub fn Init() InputState {
        return InputState{
            .Keyboard = std.mem.zeroes([256]ToggleState),
            .Mouse = std.mem.zeroInit(Mouse, .{}),
            .bMouseLockNextUpdate = false,
            .XInput = std.mem.zeroInit(XInput, .{}),
            .XInputSrc = std.mem.zeroInit(XInputRaw, .{}),
        };
    }

    pub fn Update(self: *InputState) void {
        self.XInputUpdate();
        self.KeyboardUpdate();
        self.MouseUpdate();
    }

    fn XInputUpdate(self: *InputState) void {
        const controller: u8 = 0;

        self.XInputSrc = std.mem.zeroInit(XInputRaw, .{});
        var new_state: XInputRawState = undefined;
        if (XInputGetState(controller, &new_state) == 0)
            self.XInputSrc = new_state.Gamepad;

        const buttons = comptime std.enums.values(XInputRawButton);
        for (buttons, 0..) |b, i| {
            const b_int: u16 = @intFromEnum(b);
            self.XInput.Button[i].update((self.XInputSrc.wButtons & b_int) > 0);
        }
        self.XInput.Axis[0] = @as(f32, @floatFromInt(self.XInputSrc.bLeftTrigger)) / 255;
        self.XInput.Axis[1] = @as(f32, @floatFromInt(self.XInputSrc.bRightTrigger)) / 255;
        self.XInput.Axis[2] = @as(f32, @floatFromInt(self.XInputSrc.sThumbLX)) / 32767;
        self.XInput.Axis[3] = @as(f32, @floatFromInt(self.XInputSrc.sThumbLY)) / 32767;
        self.XInput.Axis[4] = @as(f32, @floatFromInt(self.XInputSrc.sThumbRX)) / 32767;
        self.XInput.Axis[5] = @as(f32, @floatFromInt(self.XInputSrc.sThumbRY)) / 32767;
    }

    pub fn XInputGetButton(self: *InputState, button: XInputButton) ToggleState {
        return self.XInput.Button[@intFromEnum(button)];
    }

    pub fn XInputGetAxis(self: *InputState, axis: XInputAxis) f32 {
        return self.XInput.Axis[@intFromEnum(axis)];
    }

    pub fn KeyboardUpdate(self: *InputState) void {
        var kb_new: [256]u8 = undefined;
        _ = GetKeyboardState(&kb_new);

        for (kb_new, 0..) |k, i| {
            const down: u8 = k >> 7; // KB_DOWN
            const new: u8 = (down ^ @intFromEnum(self.Keyboard[i]) & 0x01) << 1; // KB_NEW
            self.Keyboard[i] = @enumFromInt(down | new);
        }
    }

    pub fn KeyboardGetRaw(self: *InputState, keycode: VirtualKey) ToggleState {
        return self.Keyboard[@as(u8, @truncate(@intFromEnum(keycode)))];
    }

    pub fn KeyboardGet(self: *InputState, keycode: VirtualKey, state: ToggleState) bool {
        return self.KeyboardGetRaw(keycode) == state;
    }

    // FIXME: add window-relative coordinates to output in OS units, not 640x480
    // old code worked properly at one point, but now behaves like the normal
    // game cursor. maybe it only worked because of dgvoodoo forcing a resize after tab-out?
    pub fn MouseUpdate(self: *InputState) void {
        var m: Point = undefined;
        var c: RECT = undefined;

        const hwnd: HWND = @ptrCast(rg.WINDOW_HWND.*);
        if (GetCursorPos(&m) > 0 and GetClientRect(hwnd, &c) > 0) {
            const s: *Mouse = &self.Mouse;

            s.RawDelta.x = m.x - s.Raw.x;
            s.RawDelta.y = m.y - s.Raw.y;
            s.Raw = m;

            // TODO: move mouse lock to state-based system
            // FIXME: game sometimes loses focus when moving mouse left
            // ClipCursor was meant to help but doesn't seem to (fully?) solve the problem
            if (self.bMouseLockNextUpdate) {
                self.bMouseLockNextUpdate = false;
                s.Raw.x = c.left + @divTrunc(c.right - c.left, 2);
                s.Raw.y = c.top + @divTrunc(c.bottom - c.top, 2);
                _ = SetCursorPos(s.Raw.x, s.Raw.y);
                //_ = ClipCursor(&static.c);
                _ = ShowCursor(0);
            }
        } else {
            self.Mouse = std.mem.zeroInit(Mouse, .{});
        }
    }

    // for one frame
    pub fn MouseLock(self: *InputState) void {
        self.bMouseLockNextUpdate = true;
    }

    pub fn MouseGetRaw(self: *InputState) Point {
        return self.Mouse.Raw;
    }

    pub fn MouseGetRawDelta(self: *InputState) Point {
        return self.Mouse.RawDelta;
    }

    //pub fn get_mouse_window() Point {
    //    return mouse.window;
    //}

    //pub fn get_mouse_window_d() Point {
    //    return mouse.window_d;
    //}

    //pub fn get_mouse_inside() st.ToggleState {
    //    return mouse.window_in;
    //}
};
