const Self = @This();

const std = @import("std");
const win32 = @import("../import/import.zig").win32;
const win32kb = win32.ui.input.keyboard_and_mouse;

const global = @import("global.zig");
const GlobalState = global.GlobalState;

const SettingsGroup = @import("util/settings.zig").SettingsGroup;
const SettingsManager = @import("util/settings.zig").SettingsManager;

// copypasted
// FIXME: deinits happen in GameEnd, see HookGameEnd.
// probably not necessary to deinit at all tho.
// one other strategy might be to set globals for stuff
// we need to keep, and go back to deinit-ing. then we also
// wouldn't have to do hash lookups constantly too.

pub const state = struct {
    pub var manager: SettingsManager = undefined;
    pub var gen: SettingsGroup = undefined;
    pub var prac: SettingsGroup = undefined;
    pub var sav: SettingsGroup = undefined;
    pub var mp: SettingsGroup = undefined;
};

pub fn init(alloc: std.mem.Allocator) void {
    state.manager = SettingsManager.init(alloc);

    state.gen = SettingsGroup.init(alloc, "general");
    state.gen.add("death_speed_mod_enable", bool, false);
    state.gen.add("death_speed_min", f32, 325);
    state.gen.add("death_speed_drop", f32, 140);
    state.gen.add("rainbow_timer_enable", bool, false);
    state.gen.add("ms_timer_enable", bool, false);
    state.gen.add("default_laps", u32, 3);
    state.gen.add("default_racers", u32, 12);
    state.manager.add(&state.gen);

    state.prac = SettingsGroup.init(alloc, "practice");
    state.prac.add("practice_tool_enable", bool, false);
    state.prac.add("overlay_enable", bool, false);
    state.manager.add(&state.prac);

    state.sav = SettingsGroup.init(alloc, "savestate");
    state.sav.add("savestate_enable", bool, false);
    state.sav.add("load_delay", u32, 500);
    state.manager.add(&state.sav);

    state.mp = SettingsGroup.init(alloc, "multiplayer");
    state.mp.add("multiplayer_mod_enable", bool, false); // working?
    state.mp.add("patch_netplay", bool, false); // working? ups ok, coll ?
    state.mp.add("netplay_guid", bool, false); // working?
    state.mp.add("netplay_r100", bool, false); // working
    state.mp.add("patch_audio", bool, false); // FIXME: crashes
    state.mp.add("patch_fonts", bool, false); // working
    state.mp.add("fonts_dump", bool, false); // working?
    state.mp.add("patch_tga_loader", bool, false); // FIXME: need tga files to verify with
    state.mp.add("patch_trigger_display", bool, false); // working
    state.manager.add(&state.mp);

    state.manager.read_ini(alloc, "annodue/settings.ini") catch unreachable;
}

pub fn deinit(gs: *GlobalState, initialized: bool) void {
    _ = initialized;
    _ = gs;
    defer state.manager.deinit();
    defer state.prac.deinit();
    defer state.gen.deinit();
    defer state.mp.deinit();
}
