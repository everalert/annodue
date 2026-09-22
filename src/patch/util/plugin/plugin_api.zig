//! formerly: GlobalFunction in core/SharedDef

// TODO: go through codebase and replace "gf" usage with "api"

const std = @import("std");

const plug = @import("plugin.zig");
const ASettingHandle = plug.ASettingHandle;
const ASettingKind = plug.ASettingKind;
const ASettingMessage = plug.ASettingMessage;
const ASettingMValue = plug.ASettingMValue;
const RAddressHandle = plug.RAddressHandle;
const GDrawLayer = plug.GDrawLayer;
const AInputXInputAxis = plug.AInputXInputAxis;
const AInputXInputButton = plug.AInputXInputButton;
const AInputPoint = plug.AInputPoint;
const AInputVirtualKey = plug.AInputVirtualKey;

// FIXME: these are only here because the functions needing them haven't had their
//  defs make their way to the typelist in plugin.zig yet
const w32 = @import("zigwin32");
const BOOL = w32.foundation.BOOL;
const ToggleState = @import("../toggle_state.zig").ToggleState;
const Handle = @import("../handle_map.zig").Handle;
const HandleStatic = @import("../handle_map_static.zig").Handle;
const r = @import("racer");
const Test = r.Entity.Test.Test;
const Trig = r.Entity.Trig.Trig;
const ModelTriggerDescription = r.Model.ModelTriggerDescription;
const TextDef = r.Text.TextDef;

// FIXME: these should go to wherever GlobalState ends up
pub const RaceState = enum(u8) { None, PreRace, Countdown, Racing, PostRace, PostRaceExiting };
pub const HangState = r.Entity.Hang.HangMenuScreen;

pub const PLUGIN_API_VERSION = 36;

// TODO: fnptr for nullable handles, or handles in general?
pub const PluginAPI = extern struct {
    // Memory
    /// get memory valid until deinit; null/0 if OOM
    AMemoryGetPermanent: *const fn (size: u32) callconv(.C) ?*anyopaque,
    /// get zero-ed memory valid until deinit; null/0 if OOM
    AMemoryGetPermanentZero: *const fn (size: u32) callconv(.C) ?*anyopaque,
    /// get memory valid until start of next frame; null/0 if OOM
    AMemoryGetTemporary: *const fn (size: u32) callconv(.C) ?*anyopaque,
    /// get zero-ed memory valid until start of next frame; null/0 if OOM
    AMemoryGetTemporaryZero: *const fn (size: u32) callconv(.C) ?*anyopaque,
    // Settings
    ASettingSave: *const fn () callconv(.C) void,
    ASettingSaveAuto: *const fn () callconv(.C) void,
    ASettingOccupy: *const fn (
        section: ASettingHandle, // originally nullable
        name: [*:0]const u8,
        value_type: ASettingKind,
        value_default: ASettingMValue,
        value_ptr: ?*anyopaque,
        fnOnChange: ?*const fn (ASettingMValue) callconv(.C) void,
    ) callconv(.C) ASettingHandle,
    ASettingVacate: *const fn (handle: ASettingHandle) callconv(.C) void,
    ASettingVacateAll: *const fn () callconv(.C) void,
    ASettingUpdate: *const fn (handle: ASettingHandle, value: ASettingMValue) callconv(.C) void,
    ASettingResetAllDefault: *const fn () callconv(.C) void,
    ASettingResetAllFile: *const fn () callconv(.C) void,
    ASettingCleanAll: *const fn () callconv(.C) void,
    ASettingSectionOccupy: *const fn (
        section: ASettingHandle, // originally nullable
        name: [*:0]const u8,
        fnOnChange: ?*const fn (arr: [*]ASettingMessage, len: usize) callconv(.C) void,
    ) callconv(.C) ASettingHandle,
    ASettingSectionVacate: *const fn (handle: ASettingHandle) callconv(.C) void,
    ASettingSectionRunUpdate: *const fn (handle: ASettingHandle) callconv(.C) void,
    ASettingSectionResetDefault: *const fn (handle: ASettingHandle) callconv(.C) void,
    ASettingSectionResetFile: *const fn (handle: ASettingHandle) callconv(.C) void,
    ASettingSectionClean: *const fn (handle: ASettingHandle) callconv(.C) void,
    // Input
    AInputKbGet: *const fn (keycode: AInputVirtualKey, state: ToggleState) callconv(.C) bool,
    AInputKbGetRaw: *const fn (keycode: AInputVirtualKey) callconv(.C) ToggleState,
    AInputMouseGet: *const fn () callconv(.C) AInputPoint,
    AInputMouseGetDelta: *const fn () callconv(.C) AInputPoint,
    AInputMouseLock: *const fn () callconv(.C) void,
    //AInputMouseIsInWindow: *const fn () callconv(.C) ToggleState,
    AInputXInputGetButton: *const fn (button: AInputXInputButton) callconv(.C) ToggleState,
    AInputXInputGetAxis: *const fn (axis: AInputXInputAxis) callconv(.C) f32,
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
    RAddressRangeAvailable: *const fn (address: u32, end: u32) callconv(.C) bool,
    RAddressRangeReserve: *const fn (address: u32, end: u32) callconv(.C) RAddressHandle,
    RAddressRangeRelease: *const fn (handle: RAddressHandle) callconv(.C) void,
    RAddressRangeRestore: *const fn (handle: RAddressHandle) callconv(.C) void,
    RAddressRangeRead: *const fn (address: u32, end: u32, buf: ?[*]u8) callconv(.C) bool,
    RAddressRangeWriteSt: *const fn (handle: RAddressHandle) callconv(.C) bool,
    RAddressRangeWriteEd: *const fn (handle: RAddressHandle) callconv(.C) void,
    RAddressRangeContainsRange: *const fn (handle: RAddressHandle, addr_st: u32, addr_ed: u32) callconv(.C) bool,
    RAddressRangeSetFlagRestoreOnRelease: *const fn (handle: RAddressHandle, flag: bool) callconv(.C) void,
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
    const info = @typeInfo(PluginAPI);

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
