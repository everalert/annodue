const Self = @This();

const std = @import("std");
const w32 = @import("zigwin32");
const w32f = w32.foundation;
const w32fs = w32.storage.file_system;

const app = @import("../appinfo.zig");
const GlobalSt = app.GLOBAL_STATE;
const GlobalFn = app.GLOBAL_FUNCTION;

const hook = @import("Hook.zig");
const allocator = @import("Allocator.zig");

const SettingsGroup = @import("../util/settings.zig").SettingsGroup;
const SettingsManager = @import("../util/settings.zig").SettingsManager;

const SETTINGS_VERSION: u32 = 1;

// TODO: default settings.ini generation that is not sorted but in order of
// adding the values
// TODO: move default settings.ini generation to settings util lib

// copypasted
// FIXME: deinits happen in GameEnd, see HookGameEnd.
// probably not necessary to deinit at all tho.
// one other strategy might be to set globals for stuff
// we need to keep, and go back to deinit-ing. then we also
// wouldn't have to do hash lookups constantly too.

pub const SettingsState = struct {
    const check_freq: u32 = 1000 / 24; // in lieu of every frame
    const load_callback: *const fn () void = hook.PluginFnCallback(.OnSettingsLoad);
    var last_check: u32 = 0;
    var last_filetime: w32f.FILETIME = undefined;
    pub var manager: SettingsManager = undefined;
    pub var gameplay: SettingsGroup = undefined;
    pub var overlay: SettingsGroup = undefined;
    pub var savestate: SettingsGroup = undefined;
    pub var multiplayer: SettingsGroup = undefined;
    pub var cam7: SettingsGroup = undefined;
    pub var inputdisplay: SettingsGroup = undefined;
    pub var qol: SettingsGroup = undefined;
    pub var cosmetic: SettingsGroup = undefined;
    pub var developer: SettingsGroup = undefined;
    pub var collisionviewer: SettingsGroup = undefined;
};

fn get(group: ?[*:0]const u8, setting: [*:0]const u8, comptime T: type) ?T {
    const sg: ?*SettingsGroup = if (group) |g| SettingsState.manager.groups.get(std.mem.span(g)) else &SettingsState.manager.global;
    return if (sg) |g| g.get(std.mem.span(setting), T) else null;
}

pub fn get_bool(group: ?[*:0]const u8, setting: [*:0]const u8) ?bool {
    return get(group, setting, bool);
}

pub fn get_i32(group: ?[*:0]const u8, setting: [*:0]const u8) ?i32 {
    return get(group, setting, i32);
}

pub fn get_u32(group: ?[*:0]const u8, setting: [*:0]const u8) ?u32 {
    return get(group, setting, u32);
}

pub fn get_f32(group: ?[*:0]const u8, setting: [*:0]const u8) ?f32 {
    return get(group, setting, f32);
}

pub fn init() void {
    const alloc = allocator.allocator();

    SettingsState.manager = SettingsManager.init(alloc);
    SettingsState.manager.global.add("SETTINGS_VERSION", u32, SETTINGS_VERSION);
    SettingsState.manager.global.add("AUTO_UPDATE", bool, true);

    // set defaults

    SettingsState.qol = SettingsGroup.init(alloc, "qol");
    SettingsState.qol.add("quick_restart_enable", bool, true);
    SettingsState.qol.add("quick_race_menu_enable", bool, true);
    SettingsState.qol.add("ms_timer_enable", bool, true);
    SettingsState.qol.add("fps_limiter_enable", bool, true);
    SettingsState.qol.add("fps_limiter_default", u32, 24);
    SettingsState.qol.add("skip_planet_cutscenes", bool, true);
    SettingsState.qol.add("skip_podium_cutscene", bool, true);
    SettingsState.qol.add("default_laps", u32, 3);
    SettingsState.qol.add("default_racers", u32, 1);
    SettingsState.qol.add("fast_countdown_enable", bool, false);
    SettingsState.qol.add("fast_countdown_duration", f32, 1.0);
    SettingsState.qol.add("fix_viewport_edges", bool, false);
    SettingsState.manager.add(&SettingsState.qol);

    SettingsState.cosmetic = SettingsGroup.init(alloc, "cosmetic");
    SettingsState.cosmetic.add("rainbow_enable", bool, false);
    SettingsState.cosmetic.add("rainbow_value_enable", bool, false);
    SettingsState.cosmetic.add("rainbow_label_enable", bool, false);
    SettingsState.cosmetic.add("rainbow_speed_enable", bool, false);
    SettingsState.cosmetic.add("patch_tga_loader", bool, false); // FIXME: need tga files to verify with
    SettingsState.cosmetic.add("patch_trigger_display", bool, false); // working
    SettingsState.cosmetic.add("patch_audio", bool, false); // FIXME: crashes
    SettingsState.cosmetic.add("patch_fonts", bool, false); // working
    SettingsState.manager.add(&SettingsState.cosmetic);

    SettingsState.cam7 = SettingsGroup.init(alloc, "cam7");
    SettingsState.cam7.add("enable", bool, true);
    SettingsState.cam7.add("flip_look_x", bool, false);
    SettingsState.cam7.add("flip_look_y", bool, false);
    SettingsState.cam7.add("stick_deadzone_inner", f32, 0.05);
    SettingsState.cam7.add("stick_deadzone_outer", f32, 0.95);
    SettingsState.cam7.add("default_move_speed", u32, 2);
    SettingsState.cam7.add("default_move_smoothing", u32, 2);
    SettingsState.cam7.add("default_rotation_speed", u32, 2);
    SettingsState.cam7.add("default_rotation_smoothing", u32, 0);
    SettingsState.cam7.add("mouse_dpi", u32, 1600);
    SettingsState.cam7.add("mouse_cm360", f32, 24.0);
    SettingsState.manager.add(&SettingsState.cam7);

    SettingsState.savestate = SettingsGroup.init(alloc, "savestate");
    SettingsState.savestate.add("enable", bool, true);
    SettingsState.savestate.add("load_delay", u32, 500);
    SettingsState.manager.add(&SettingsState.savestate);

    SettingsState.inputdisplay = SettingsGroup.init(alloc, "inputdisplay");
    SettingsState.inputdisplay.add("enable", bool, false);
    SettingsState.inputdisplay.add("pos_x", i32, 420);
    SettingsState.inputdisplay.add("pos_y", i32, 432);
    SettingsState.manager.add(&SettingsState.inputdisplay);

    SettingsState.overlay = SettingsGroup.init(alloc, "overlay");
    SettingsState.overlay.add("enable", bool, false);
    SettingsState.manager.add(&SettingsState.overlay);

    SettingsState.multiplayer = SettingsGroup.init(alloc, "multiplayer");
    SettingsState.multiplayer.add("enable", bool, false); // working? TODO: check collisions
    SettingsState.multiplayer.add("patch_guid", bool, false); // working?
    SettingsState.multiplayer.add("patch_r100", bool, false); // working
    SettingsState.manager.add(&SettingsState.multiplayer);

    SettingsState.gameplay = SettingsGroup.init(alloc, "gameplay");
    SettingsState.gameplay.add("enable", bool, false);
    SettingsState.gameplay.add("death_speed_mod_enable", bool, false);
    SettingsState.gameplay.add("death_speed_min", f32, 325);
    SettingsState.gameplay.add("death_speed_drop", f32, 140);
    SettingsState.manager.add(&SettingsState.gameplay);

    SettingsState.collisionviewer = SettingsGroup.init(alloc, "collisionviewer");
    SettingsState.collisionviewer.add("depth_bias", i32, 10);
    SettingsState.manager.add(&SettingsState.collisionviewer);

    SettingsState.developer = SettingsGroup.init(alloc, "developer");
    SettingsState.developer.add("dump_fonts", bool, false); // working?
    SettingsState.developer.add("visualize_matrices", bool, false);
    SettingsState.manager.add(&SettingsState.developer);

    // load settings

    // FIXME: MAYBE remove this, and make all the dependencies do settings-based
    // initialization via OnSettingsLoad (not sure if it would change much about DX)
    defer _ = LoadSettings();

    const file = std.fs.cwd().createFile("annodue/settings.ini", .{ .exclusive = true }) catch return;
    defer file.close();

    const mitems = SettingsState.manager.global.sorted() catch return;
    defer mitems.deinit();
    for (mitems.items) |item| {
        const val = item.value.allocFmt(alloc) catch continue;
        defer alloc.free(val);
        const str = std.fmt.allocPrint(alloc, "{s} = {s}\n", .{ item.key.*, val }) catch continue;
        defer alloc.free(str);
        _ = file.write(str) catch continue;
    }
    _ = file.write("\n") catch {};

    var groups = SettingsState.manager.sorted() catch return;
    defer groups.deinit();
    for (groups.items) |group| {
        if (group.value.values.count() == 0) continue;

        const header = std.fmt.allocPrint(alloc, "[{s}]\n", .{group.key.*}) catch continue;
        defer alloc.free(header);
        _ = file.write(header) catch continue;

        const items = group.value.sorted() catch continue;
        defer items.deinit();
        for (items.items) |item| {
            const val = item.value.allocFmt(alloc) catch continue;
            defer alloc.free(val);
            const str = std.fmt.allocPrint(alloc, "{s} = {s}\n", .{ item.key.*, val }) catch continue;
            defer alloc.free(str);
            _ = file.write(str) catch continue;
        }
        _ = file.write("\n") catch continue;
    }
}

// FIXME: copied from hook.zig; move both to util?
fn filetime_eql(t1: *w32f.FILETIME, t2: *w32f.FILETIME) bool {
    return (t1.dwLowDateTime == t2.dwLowDateTime and
        t1.dwHighDateTime == t2.dwHighDateTime);
}

fn LoadSettings() bool {
    var fd: w32fs.WIN32_FIND_DATAA = undefined;
    _ = w32fs.FindFirstFileA("annodue/settings.ini", &fd);
    if (filetime_eql(&fd.ftLastWriteTime, &SettingsState.last_filetime))
        return false;

    const alloc = allocator.allocator();
    SettingsState.manager.read_ini(alloc, "annodue/settings.ini") catch return false;
    SettingsState.last_filetime = fd.ftLastWriteTime;

    return true;
}

// HOOK FUNCTIONS

pub fn GameLoopB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    if (gs.timestamp > SettingsState.last_check + SettingsState.check_freq)
        if (LoadSettings())
            SettingsState.load_callback();
    SettingsState.last_check = gs.timestamp;
}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    defer SettingsState.manager.deinit();

    defer SettingsState.overlay.deinit();
    defer SettingsState.savestate.deinit();
    defer SettingsState.gameplay.deinit();
    defer SettingsState.multiplayer.deinit();
    defer SettingsState.cam7.deinit();
    defer SettingsState.inputdisplay.deinit();
    defer SettingsState.qol.deinit();
    defer SettingsState.cosmetic.deinit();
    defer SettingsState.developer.deinit();
    defer SettingsState.collisionviewer.deinit();
}
