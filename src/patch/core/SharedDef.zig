const std = @import("std");

const HWND = std.os.windows.HWND;
const HINSTANCE = std.os.windows.HINSTANCE;
const BOOL = std.os.windows.BOOL;

const w32 = @import("zigwin32");
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;
const POINT = w32.foundation.POINT;

const ActiveState = @import("../util/active_state.zig").ActiveState;
const Handle = @import("../util/handle_map.zig").Handle;
const HandleStatic = @import("../util/handle_map_static.zig").Handle;

const XINPUT_GAMEPAD_BUTTON_INDEX = @import("Input.zig").XINPUT_GAMEPAD_BUTTON_INDEX;
const XINPUT_GAMEPAD_AXIS_INDEX = @import("Input.zig").XINPUT_GAMEPAD_AXIS_INDEX;
const GDrawLayer = @import("GDraw.zig").GDrawLayer;

const r = @import("racer");
const Test = r.Entity.Test.Test;
const Trig = r.Entity.Trig.Trig;
const ModelTriggerDescription = r.Model.ModelTriggerDescription;
const TextDef = r.Text.TextDef;

const RaceState = enum(u8) { None, PreRace, Countdown, Racing, PostRace, PostRaceExiting };

pub const GLOBAL_STATE_VERSION = 5;

// TODO: move all references to patch_memory to use internal allocator; add
// allocator interface to GlobalFunction
// TODO: move all the common game check stuff from plugins/modules to here; cleanup
// TODO: add index of currently consumed loaded tga IDs, since they are arbitrarily assigned
//   also, some kind of interface plugins can use to avoid clashes
//   list of stuff to update when it's made:
//     inputdisplay, practice mode vis, spare camstates used
pub const GlobalState = extern struct {
    patch_memory: [*]u8 = undefined,
    patch_size: usize = undefined,
    patch_offset: usize = undefined,

    init_late_passed: bool = false,

    practice_mode: bool = false,

    hwnd: ?HWND = null,
    hinstance: ?HINSTANCE = null,

    dt_f: f32 = 0,
    fps: f32 = 0,
    fps_avg: f32 = 0,
    timestamp: u32 = 0,
    framecount: u32 = 0,

    in_race: ActiveState = .Off,
    race_state: RaceState = .None,
    race_state_prev: RaceState = .None,
    race_state_new: bool = false,
    player: extern struct {
        upgrades: bool = false,
        upgrades_lv: [7]u8 = undefined,
        upgrades_hp: [7]u8 = undefined,

        flags1: u32 = 0,
        boosting: ActiveState = .Off,
        underheating: ActiveState = .On,
        overheating: ActiveState = .Off,
        dead: ActiveState = .Off,
        deaths: u32 = 0,

        heat_rate: f32 = 0,
        cool_rate: f32 = 0,
        heat: f32 = 0,
    } = .{},
};

pub const GLOBAL_FUNCTION_VERSION = 20;

pub const GlobalFunction = extern struct {
    // Settings
    SettingGetB: *const fn (group: ?[*:0]const u8, setting: [*:0]const u8) ?bool,
    SettingGetI: *const fn (group: ?[*:0]const u8, setting: [*:0]const u8) ?i32,
    SettingGetU: *const fn (group: ?[*:0]const u8, setting: [*:0]const u8) ?u32,
    SettingGetF: *const fn (group: ?[*:0]const u8, setting: [*:0]const u8) ?f32,
    // Input
    InputGetKb: *const fn (keycode: VIRTUAL_KEY, state: ActiveState) bool,
    InputGetKbRaw: *const fn (keycode: VIRTUAL_KEY) ActiveState,
    InputGetMouse: *const fn () callconv(.C) POINT,
    InputGetMouseDelta: *const fn () callconv(.C) POINT,
    InputLockMouse: *const fn () callconv(.C) void,
    //InputGetMouseInWindow: *const fn () callconv(.C) ActiveState,
    InputGetXInputButton: *const fn (button: XINPUT_GAMEPAD_BUTTON_INDEX) ActiveState,
    InputGetXInputAxis: *const fn (axis: XINPUT_GAMEPAD_AXIS_INDEX) f32,
    // Game
    GDrawText: *const fn (layer: GDrawLayer, text: ?*TextDef) bool,
    //GDrawTextBox: *const fn (layer: GDrawLayer, text: ?*TextDef, pad_x: i16, pad_y: i16, rect_color: u32) bool,
    GDrawRect: *const fn (layer: GDrawLayer, x: i16, y: i16, w: i16, h: i16, color: u32) bool,
    GFreezeEnable: *const fn (o: [*:0]const u8) bool,
    GFreezeDisable: *const fn (o: [*:0]const u8) bool,
    GFreezeIsFrozen: *const fn () bool,
    GHideRaceUIEnable: *const fn (o: [*:0]const u8) bool,
    GHideRaceUIDisable: *const fn (o: [*:0]const u8) bool,
    GHideRaceUIIsHidden: *const fn () bool,
    // Toast
    ToastNew: *const fn (text: [*:0]const u8, color: u32) callconv(.C) bool,
    // Resources
    RTerrainRequest: *const fn (
        bit: u16,
        group: u16,
        fnTerrain: *const fn (*Test) callconv(.C) void,
    ) callconv(.C) HandleStatic(u16),
    RTerrainRelease: *const fn (HandleStatic(u16)) callconv(.C) void,
    RTerrainReleaseAll: *const fn () callconv(.C) void,
    RTriggerRequest: *const fn (
        id: u16,
        fnTrigger: *const fn (*Trig, *Test, BOOL, u16) callconv(.C) void,
        fnInit: ?*const fn (*ModelTriggerDescription, u32, u16) callconv(.C) void,
        fnDestroy: ?*const fn (*Trig, u16) callconv(.C) bool,
        fnUpdate: ?*const fn (*Trig, u16) callconv(.C) void,
    ) callconv(.C) Handle(u16),
    RTriggerRelease: *const fn (Handle(u16)) callconv(.C) void,
    RTriggerReleaseAll: *const fn () callconv(.C) void,
};
