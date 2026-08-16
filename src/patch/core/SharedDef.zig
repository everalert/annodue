const std = @import("std");

const w32 = @import("zigwin32");
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;
const POINT = w32.foundation.POINT;
const BOOL = w32.foundation.BOOL;
const HWND = w32.foundation.HWND;
const HINSTANCE = w32.foundation.HINSTANCE;

const ToggleState = @import("../util/toggle_state.zig").ToggleState;
const Handle = @import("../util/handle_map.zig").Handle;
const HandleStatic = @import("../util/handle_map_static.zig").Handle;
const HandleSOA = @import("../util/handle_map_soa.zig").Handle;

const XINPUT_GAMEPAD_BUTTON_INDEX = @import("Input.zig").XINPUT_GAMEPAD_BUTTON_INDEX;
const XINPUT_GAMEPAD_AXIS_INDEX = @import("Input.zig").XINPUT_GAMEPAD_AXIS_INDEX;
const ASettingSent = @import("ASettings.zig").ASettingSent;
const ASetting = @import("ASettings.zig").Setting;
const ASettingSection = @import("ASettings.zig").Section;
const GDrawLayer = @import("GDraw.zig").GDrawLayer;

const r = @import("racer");
const Test = r.Entity.Test.Test;
const TestFlags1 = r.Entity.Test.TEST_FLAGS1;
const Trig = r.Entity.Trig.Trig;
const ModelTriggerDescription = r.Model.ModelTriggerDescription;
const TextDef = r.Text.TextDef;

pub const RaceState = enum(u8) { None, PreRace, Countdown, Racing, PostRace, PostRaceExiting };
pub const HangState = r.Entity.Hang.HangMenuScreen;

pub const GLOBAL_STATE_VERSION = 9;

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

    window_in_foreground: bool = true,

    //dt_f: f32 = 0,
    //fps: f32 = 0,
    fps_avg: f32 = 0,

    in_race: ToggleState = .Off,
    race_state: RaceState = .None,
    race_state_prev: RaceState = .None,
    race_state_new: bool = false,
    hang_state: HangState = .None,
    hang_state_prev: HangState = .None,
    hang_state_new: bool = false,
    player: extern struct {
        boosting: ToggleState = .Off,
        boost_charging: ToggleState = .Off,
        boost_ready: ToggleState = .Off,
        underheating: ToggleState = .On,
        overheating: ToggleState = .Off,
        dead: ToggleState = .Off,
        deaths: u32 = 0,
    } = .{},
};

pub const GLOBAL_FUNCTION_VERSION = 33;

// TODO: fnptr for nullable handles, or handles in general?
pub const GlobalFunction = extern struct {
    // Settings
    ASettingSave: *const fn () callconv(.C) void,
    ASettingSaveAuto: *const fn () callconv(.C) void,
    ASettingOccupy: *const fn (
        section: Handle(u16), // originally nullable
        name: [*:0]const u8,
        value_type: ASetting.Type,
        value_default: ASettingSent.Value,
        value_ptr: ?*anyopaque,
        fnOnChange: ?*const fn (ASettingSent.Value) callconv(.C) void,
    ) callconv(.C) Handle(u16),
    ASettingVacate: *const fn (handle: Handle(u16)) callconv(.C) void,
    ASettingVacateAll: *const fn () callconv(.C) void,
    ASettingUpdate: *const fn (handle: Handle(u16), value: ASettingSent.Value) callconv(.C) void,
    ASettingResetAllDefault: *const fn () callconv(.C) void,
    ASettingResetAllFile: *const fn () callconv(.C) void,
    ASettingCleanAll: *const fn () callconv(.C) void,
    ASettingSectionOccupy: *const fn (
        section: Handle(u16), // originally nullable
        name: [*:0]const u8,
        fnOnChange: ?*const fn (arr: [*]ASettingSent, len: usize) callconv(.C) void,
    ) callconv(.C) Handle(u16),
    ASettingSectionVacate: *const fn (handle: Handle(u16)) callconv(.C) void,
    ASettingSectionRunUpdate: *const fn (handle: Handle(u16)) callconv(.C) void,
    ASettingSectionResetDefault: *const fn (handle: Handle(u16)) callconv(.C) void,
    ASettingSectionResetFile: *const fn (handle: Handle(u16)) callconv(.C) void,
    ASettingSectionClean: *const fn (handle: Handle(u16)) callconv(.C) void,
    // Input
    InputGetKb: *const fn (keycode: VIRTUAL_KEY, state: ToggleState) callconv(.C) bool,
    InputGetKbRaw: *const fn (keycode: VIRTUAL_KEY) callconv(.C) ToggleState,
    InputGetMouse: *const fn () callconv(.C) POINT,
    InputGetMouseDelta: *const fn () callconv(.C) POINT,
    InputLockMouse: *const fn () callconv(.C) void,
    //InputGetMouseInWindow: *const fn () callconv(.C) ToggleState,
    InputGetXInputButton: *const fn (button: XINPUT_GAMEPAD_BUTTON_INDEX) callconv(.C) ToggleState,
    InputGetXInputAxis: *const fn (axis: XINPUT_GAMEPAD_AXIS_INDEX) callconv(.C) f32,
    // Game
    GDrawText: *const fn (layer: GDrawLayer, text: ?*TextDef) callconv(.C) bool,
    //GDrawTextBox: *const fn (layer: GDrawLayer, text: ?*TextDef, pad_x: i16, pad_y: i16, rect_color: u32) bool,
    GDrawRect: *const fn (layer: GDrawLayer, x: i16, y: i16, w: i16, h: i16, color: u32) callconv(.C) bool,
    GDrawRectBdr: *const fn (layer: GDrawLayer, x: i16, y: i16, w: i16, h: i16, color: u32, bdr_w: i16, bdr_col: u32) callconv(.C) bool,
    GFreezeOn: *const fn () callconv(.C) bool,
    GFreezeOff: *const fn () callconv(.C) bool,
    GFreezeIsOn: *const fn () callconv(.C) bool,
    GHideRaceUIOn: *const fn () callconv(.C) bool,
    GHideRaceUIOff: *const fn () callconv(.C) bool,
    GHideRaceUIIsOn: *const fn () callconv(.C) bool,
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
    // State;  previously accessed via 'global state'
    SInitLatePassed: *const fn () callconv(.C) bool, // init_late_passed
    SPracticeMode: *const fn () callconv(.C) bool, // practice_mode, WARN: some funcs write to this
    SWindowInForeground: *const fn () callconv(.C) bool, // window_in_foreground
    SFPSAvg: *const fn () callconv(.C) f32, // fps_avg
    SInRace: *const fn () callconv(.C) ToggleState, // in_race
    SRaceState: *const fn () callconv(.C) RaceState, // race_state
    SRaceStatePrev: *const fn () callconv(.C) RaceState, // race_state_prev
    SRaceStateNew: *const fn () callconv(.C) bool, // race_state_new
    SHangState: *const fn () callconv(.C) HangState, // hang_state
    SHangStatePrev: *const fn () callconv(.C) HangState, // hang_state_prev
    SHangStateNew: *const fn () callconv(.C) bool, // hang_state_new
    SPlayerBoosting: *const fn () callconv(.C) ToggleState, // player -> boosting
    SPlayerBoostCharging: *const fn () callconv(.C) ToggleState, // player -> boost_charging
    SPlayerBoostReady: *const fn () callconv(.C) ToggleState, // player -> boost_ready
    SPlayerUnderheating: *const fn () callconv(.C) ToggleState, // player -> underheating
    SPlayerOverheating: *const fn () callconv(.C) ToggleState, // player -> overheating
    SPlayerDead: *const fn () callconv(.C) ToggleState, // player -> dead
    SPlayerDeaths: *const fn () callconv(.C) u32, // player -> deaths
};

comptime {
    const info = @typeInfo(GlobalFunction);

    if (info.Struct.layout != .Extern)
        @compileError("GlobalFunction must have Extern layout");

    for (info.Struct.fields) |field| {
        const field_info = @typeInfo(field.type);
        const fn_info = @typeInfo(field_info.Pointer.child);
        if (fn_info.Fn.calling_convention != .C) {
            const m = std.fmt.comptimePrint("GlobalFunction: {s} must use C calling convention", .{field.name});
            @compileError(m);
        }
    }
}
