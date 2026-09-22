//! annodue input api
//!
//! internal dependencies: (none) (NOTE: initialized by plugin api)

const std = @import("std");
const assert = std.debug.assert;

const core_input = @import("../util/core/core_input.zig");
const InputState = core_input.InputState;

const plug = @import("../util/plugin/plugin.zig");
const AInputXInputAxis = plug.AInputXInputAxis;
const AInputXInputButton = plug.AInputXInputButton;
const AInputPoint = plug.AInputPoint;
const AInputVirtualKey = plug.AInputVirtualKey;

const ToggleState = @import("../util/toggle_state.zig").ToggleState;

const PluginAPI = @import("../util/root.zig").PluginAPI;

const Input = struct {
    var bInitialized: bool = false;
    var State: InputState = undefined;
};

//------------------------------------------------------------------------------
// annodue hooks

pub fn OnInit(_: *PluginAPI) callconv(.C) void {
    Input.State = InputState.Init();
    Input.bInitialized = true;
}

pub fn OnInitLate(_: *PluginAPI) callconv(.C) void {}

pub fn OnDeinit(_: *PluginAPI) callconv(.C) void {}

pub fn InputUpdateB(_: *PluginAPI) callconv(.C) void {
    assert(Input.bInitialized);
    Input.State.Update();
}

//------------------------------------------------------------------------------
// annodue api

//...
pub fn AInputKbGet(keycode: AInputVirtualKey, state: ToggleState) callconv(.C) bool {
    assert(Input.bInitialized);
    return Input.State.KeyboardGet(keycode, state);
}

pub fn AInputKbGetRaw(keycode: AInputVirtualKey) callconv(.C) ToggleState {
    assert(Input.bInitialized);
    return Input.State.KeyboardGetRaw(keycode);
}

pub fn AInputMouseGet() callconv(.C) AInputPoint {
    assert(Input.bInitialized);
    return Input.State.MouseGetRaw();
}

pub fn AInputMouseGetDelta() callconv(.C) AInputPoint {
    assert(Input.bInitialized);
    return Input.State.MouseGetRawDelta();
}

pub fn AInputMouseLock() callconv(.C) void {
    assert(Input.bInitialized);
    Input.State.MouseLock();
}

// pub fn AInputMouseIsInWindow() callconv(.C) ToggleState {}

pub fn AInputXInputGetButton(button: AInputXInputButton) callconv(.C) ToggleState {
    assert(Input.bInitialized);
    return Input.State.XInputGetButton(button);
}

pub fn AInputXInputGetAxis(axis: AInputXInputAxis) callconv(.C) f32 {
    assert(Input.bInitialized);
    return Input.State.XInputGetAxis(axis);
}
