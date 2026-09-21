const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const EnumSet = std.EnumSet;
const bufPrintZ = std.fmt.bufPrintZ;
const assert = std.debug.assert;

const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const WorkingOwner = @import("AHook.zig").PluginState.WorkingOwner;
const WorkingOwnerIsSystem = @import("AHook.zig").PluginState.WorkingOwnerIsSystem;

const core_settings = @import("../util/core/core_settings.zig");
const SettingManager = core_settings.SettingManager;

const ADAPI = @import("../util/api/api.zig");
const SettingKind = ADAPI.ASettingKind;
const SettingMessage = ADAPI.ASettingMessage;
const SettingMValue = ADAPI.ASettingMValue;
const SettingHandle = ADAPI.ASettingHandle;
const SETTING_HANDLE_NULL = ADAPI.ASETTING_HANDLE_NULL;

const MiB = @import("../util/base/base_memory.zig").MiB;

const r = @import("racer");
const rt = r.Text;
const rti = r.Time;

// PLUGIN DEVELOPER NOTES
// - use ASettingSectionOccupy to define a setting category
// - then, use ASettingOccupy to assign settings to the category
// - prefer doing this setup during OnInit, and prefer using plugin name for
//   section to avoid naming collisions
// - define setting value_ptr to save you the trouble of updating your local value manually
// - define setting fnOnChange to do any post-processing on setting update automatically
// - setting callback and pointer update will happen after setting is occupied, whenever
//   the value changes on file, and when you call ASettingUpdate
// - define section fnOnChange to do any settings coordination needed, e.g. for
//   multi-setting derived values
// - section callback will run after OnInit, and whenever values change on file; call
//   ASettingSectionRunUpdate to manually run the section callback, e.g. after closing
//   a related plugin menu
// - if update callbacks for both an individual setting and its section are
//   defined, the setting's callback will run first
// - various cleanup functions are available in the api; batch vacating will be
//   done for you after OnDeinit
// - see official plugin source code for usage examples; cam7 is a good place to start

const SCRATCH_BUFFER_SIZE = MiB(u32, 2);

const FILENAME_WORK = "annodue/settings.ini";
const FILENAME_TEST = "annodue/settings_test.ini";
const FILENAME_ACTIVE = FILENAME_WORK;

const SettingsState = struct {
    var bInitialized: bool = false;
    var Manager: SettingManager = undefined;
};

// TODO: remove dependency on importing DEFAULT_ID, probably by having anything
//  taking an id to also take null and use DEFAULT_ID internally if null; i.e.
//  make it so that users don't need to know the default id
pub fn Init(arena_perm: Allocator) !void {
    var memory = try arena_perm.create([SCRATCH_BUFFER_SIZE]u8);
    try SettingsState.Manager.Init(memory, FILENAME_ACTIVE);
    SettingsState.bInitialized = true;
}

pub fn Deinit() !void {
    assert(SettingsState.bInitialized);
    try SettingsState.Manager.saveAuto();
    SettingsState.Manager.Deinit();
}

//------------------------------------------------------------------------------
// annodue hooks

pub fn OnInit(_: *GlobalFn) callconv(.C) void {}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

pub fn OnPluginInitA(owner: u16) callconv(.C) void {
    SettingsState.Manager.sectionRunUpdateOwner(owner);
}

pub fn OnPluginDeinitA(owner: u16) callconv(.C) void {
    SettingsState.Manager.vacateOwner(owner);
}

pub fn GameLoopB(gf: *GlobalFn) callconv(.C) void {
    // create settings.ini very early, but late enough that all plugins/subsystems
    // have had a chance to register their settings in either Init or InitLate
    if (rti.FRAMECOUNT.* == 1)
        SettingsState.Manager.saveAuto() catch {};

    // keep settings file updated through any load or hang/race state transition
    if (gf.SInRace().new() or gf.SRaceStateNew() or gf.SHangStateNew())
        SettingsState.Manager.saveAuto() catch {};

    SettingsState.Manager.hot_reload.Update(rti.TIMESTAMP.*);
}

//------------------------------------------------------------------------------
// annodue api

// TODO: generally - make the plugin-facing stuff operate under 'plugin' section,
// which is initialized internally; same for core, identify via id range check.
// i.e. settings tree looks like this after moving to json-based settings
// [root]
// - <global stuff goes here>
// - core
// -- <insert here when core module using ASetting* with null parent>
// - plugin
// -- <insert here when plugin using ASetting* with null parent>

/// take ownership of a section and apply a definition
/// @section        section handle of desired parent as received from ASettingSectionOccupy; use
///                 NullHandle for no parent
/// @name           identifying string for section; max 63 chars, used to represent the section on file
/// @fnOnChange     callback function that will be run on all recently updated settings in this section
///                 collectively when ASettingSectionRunUpdate is called; use this to post-process
///                 settings that are needed to work in tandem to derive a value
/// @return         handle to section
pub fn ASectionOccupy(
    section: SettingHandle,
    name: [*:0]const u8,
    fnOnChange: ?*const fn ([*]SettingMessage, usize) callconv(.C) void,
) callconv(.C) SettingHandle {
    assert(SettingsState.bInitialized);
    return SettingsState.Manager.sectionOccupy(
        WorkingOwner(),
        if (section.isNull()) null else section,
        name,
        fnOnChange,
    ) catch SETTING_HANDLE_NULL;
}

/// release ownership of a section and all its children, automatically running
/// ASettingVacate as needed.
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionVacate(handle: SettingHandle) callconv(.C) void {
    assert(SettingsState.bInitialized);
    SettingsState.Manager.sectionVacate(handle);
}

/// manually call fnOnChange section callback on any 'changed' settings
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionRunUpdate(handle: SettingHandle) callconv(.C) void {
    assert(SettingsState.bInitialized);
    SettingsState.Manager.sectionRunUpdate(handle);
}

/// revert entries under the given section back to owner-defined defaults
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionResetDefault(handle: SettingHandle) callconv(.C) void {
    assert(SettingsState.bInitialized);
    SettingsState.Manager.sectionResetToDefaults(handle);
}

/// revert entries under the given section back to values on file
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionResetFile(handle: SettingHandle) callconv(.C) void {
    assert(SettingsState.bInitialized);
    SettingsState.Manager.sectionResetToSaved(handle);
}

/// remove superfluous entries loaded from file under the given section
/// will be reflected in the settings file on the following save write
/// @handle     section handle as received from ASettingSectionOccupy
pub fn ASectionClean(handle: SettingHandle) callconv(.C) void {
    assert(SettingsState.bInitialized);
    SettingsState.Manager.sectionResetToDefaults(handle);
}

// FIXME: logging - error before returning NullHandle (do same with ASectionOccupy)
/// take ownership of a setting and apply a definition
/// setting will be rejected if caller is plugin and no valid section handle is provided
/// @section        section handle of desired parent as received from ASettingSectionOccupy; use
///                 NullHandle for no parent
/// @name           identifying string for setting; max 63 chars, used to represent the setting on file
/// @value_type     enum value corresponding to string, u32, i32, f32 or bool types. max 63 chars for strings
/// @value_default  union interpreted as the type specified by @value_type
/// @value_ptr      memory location to be automatically updated with value via ASettingUpdate
/// @fnOnChange     callback function that will be run when the value is updated with ASettingUpdate
/// @return         handle to setting
pub fn ASettingOccupy(
    section: SettingHandle,
    name: [*:0]const u8,
    value_type: SettingKind,
    value_default: SettingMValue,
    value_ptr: ?*anyopaque,
    fnOnChange: ?*const fn (SettingMValue) callconv(.C) void,
) callconv(.C) SettingHandle {
    assert(SettingsState.bInitialized);
    if (!WorkingOwnerIsSystem() and section.isNull()) return SETTING_HANDLE_NULL;
    return SettingsState.Manager.settingOccupy(
        WorkingOwner(),
        if (section.isNull()) null else section,
        name,
        value_type,
        value_default,
        value_ptr,
        fnOnChange,
    ) catch SETTING_HANDLE_NULL;
}

/// release ownership of a setting, clearing its definition and internally
/// returning the value to raw (string-formatted) data.
/// @handle     setting handle as received from ASettingOccupy
pub fn ASettingVacate(handle: SettingHandle) callconv(.C) void {
    assert(SettingsState.bInitialized);
    SettingsState.Manager.settingVacate(handle);
}

/// update setting with a new value, passing on the value to the defined
/// external sources.
/// @handle     setting handle as received from ASettingOccupy
/// @value      union interpreted as the type defined with ASettingOccupy
pub fn ASettingUpdate(handle: SettingHandle, value: SettingMValue) callconv(.C) void {
    assert(SettingsState.bInitialized);
    SettingsState.Manager.settingUpdate(handle, value);
}

/// release ownership and definitions of all sections and settings associated
/// with the caller.
/// for internal use; will do nothing if caller is plugin
pub fn AVacateAll() callconv(.C) void {
    assert(SettingsState.bInitialized);
    if (!WorkingOwnerIsSystem()) return;
    SettingsState.Manager.vacateOwner(WorkingOwner());
}

/// revert all entries back to owner-defined defaults
/// for internal use; will do nothing if caller is plugin
pub fn ASettingResetAllDefault() callconv(.C) void {
    assert(SettingsState.bInitialized);
    if (!WorkingOwnerIsSystem()) return;
    SettingsState.Manager.settingResetAllToDefaults();
}

/// revert all entries back to values on file
/// for internal use; will do nothing if caller is plugin
pub fn ASettingResetAllFile() callconv(.C) void {
    assert(SettingsState.bInitialized);
    if (!WorkingOwnerIsSystem()) return;
    SettingsState.Manager.settingResetAllToSaved();
}

/// remove all superfluous entries loaded from file
/// will be reflected in the settings file on the following save write
/// for internal use; will do nothing if caller is plugin
pub fn ASettingCleanAll() callconv(.C) void {
    assert(SettingsState.bInitialized);
    if (!WorkingOwnerIsSystem()) return;
    SettingsState.Manager.settingRemoveAllVacant();
}

/// manually trigger write of settings file
/// for internal use; will do nothing if caller is plugin
pub fn ASave() callconv(.C) void {
    assert(SettingsState.bInitialized);
    if (!WorkingOwnerIsSystem()) return;
    SettingsState.Manager.save() catch {};
}

/// create checkpoint for writing of settings file
/// file will only be written if user has enabled autosave
pub fn ASaveAuto() callconv(.C) void {
    assert(SettingsState.bInitialized);
    SettingsState.Manager.saveAuto() catch {};
}

// -----------------------------------------------------------------------------
// DEBUGGING & TESTING

// TODO: maybe adapt for test script/debugging
// TODO: also maybe adapt for json settings (nesting, etc.)
fn drawSettings(gf: *GlobalFn, section: ?SettingHandle, x_ref: *i16, y_ref: *i16) void {
    for (SettingsState.Manager.data_settings.values.items) |value| {
        if ((section == null) != (value.section == null)) continue;
        if (section != null and
            (value.section.?.generation != section.?.generation or
            value.section.?.index != section.?.index)) continue;

        _ = gf.GDrawText(.Debug, rt.hMakeText(x_ref.*, y_ref.*, "{s}", .{value.name}, null, null) catch null);
        _ = gf.GDrawText(.Debug, switch (value.value_type) {
            .B => rt.hMakeText(256, y_ref.*, "{any}", .{value.value.b}, null, null) catch null,
            .F => rt.hMakeText(256, y_ref.*, "{d:4.2}", .{value.value.f}, null, null) catch null,
            .U => rt.hMakeText(256, y_ref.*, "{d}", .{value.value.u}, null, null) catch null,
            .I => rt.hMakeText(256, y_ref.*, "{d}", .{value.value.i}, null, null) catch null,
            else => rt.hMakeText(256, y_ref.*, "{s}", .{value.value.str}, null, null) catch null,
        });
        _ = gf.GDrawText(.Debug, switch (value.value_type) {
            .B => rt.hMakeText(312, y_ref.*, "{any}", .{value.value_default.b}, null, null) catch null,
            .F => rt.hMakeText(312, y_ref.*, "{d:4.2}", .{value.value_default.f}, null, null) catch null,
            .U => rt.hMakeText(312, y_ref.*, "{d}", .{value.value_default.u}, null, null) catch null,
            .I => rt.hMakeText(312, y_ref.*, "{d}", .{value.value_default.i}, null, null) catch null,
            .Str => rt.hMakeText(312, y_ref.*, "{s}", .{value.value_default.str}, null, null) catch null,
            .None => null,
        });
        _ = gf.GDrawText(.Debug, rt.hMakeText(368, y_ref.*, "{s}", .{@tagName(value.value_type)}, null, null) catch null);
        y_ref.* += 10;
    }

    for (0..SettingsState.Manager.data_sections.values.items.len) |i| {
        const value: *core_settings.Section = &SettingsState.Manager.data_sections.values.items[i];
        if ((section == null) != (value.section == null)) continue;
        if (section != null and
            (value.section.?.generation != section.?.generation or
            value.section.?.index != section.?.index)) continue;

        //y_ref.* += 4;
        _ = gf.GDrawText(.Debug, rt.hMakeText(x_ref.*, y_ref.*, "{s}", .{value.name}, null, null) catch null);
        y_ref.* += 10;

        x_ref.* += 12;
        const handle: SettingHandle = SettingsState.Manager.data_sections.handles.items[i];
        drawSettings(gf, handle, x_ref, y_ref);
        x_ref.* -= 12;
    }
}

// TODO: adapt for debug features
fn drawSettingsDebugPanel(gf: *GlobalFn) void {
    if (!gf.InputGetKbRaw(.RSHIFT).on()) return;

    const s = struct {
        const rate: f32 = 300;
        var y_off: i16 = 0;
    };

    _ = gf.GDrawRect(.Debug, 0, 0, 416, 480, 0x000020E0);
    var x: i16 = 8;
    var y: i16 = 8 + s.y_off;
    drawSettings(gf, null, &x, &y);

    var h: i16 = y - s.y_off;
    var dif: i16 = @intFromFloat(gf.SDt() * s.rate);
    if (gf.InputGetKbRaw(.PRIOR).on()) s.y_off = @min(s.y_off + dif, 0); // scroll up
    if (gf.InputGetKbRaw(.NEXT).on()) s.y_off = std.math.clamp(s.y_off - dif, -h + 480 - 8, 0); // scroll dn
}
