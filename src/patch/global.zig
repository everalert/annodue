const Self = @This();

const std = @import("std");
const win = std.os.windows;

const settings = @import("settings.zig");
const s = settings.state;

const st = @import("util/active_state.zig");
const xinput = @import("util/xinput.zig");
const dbg = @import("util/debug.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;
const w32xc = w32.ui.input.xbox_controller;
const w32wm = w32.ui.windows_and_messaging;
const KS_DOWN: i16 = -1;
const KS_PRESSED: i16 = 1; // since last call

// VERSION

const VersionTag = enum(u32) {
    None,
    Alpha,
    Beta,
    ReleaseCandidate,
};

// TODO: see: std.SemanticVersion
pub const Version = struct {
    pub const major: u32 = 0;
    pub const minor: u32 = 0;
    pub const patch: u32 = 1;
    pub const tag_type: VersionTag = .None;
    pub const tag_no: u32 = 0;
    pub const build: u32 = 112; // based on git commits
};

// TODO: include tag when appropriate
pub const VersionStr: [:0]u8 = s: {
    var buf: [127:0]u8 = undefined;
    break :s std.fmt.bufPrintZ(&buf, "Annodue {d}.{d}.{d}.{d}", .{
        Version.major,
        Version.minor,
        Version.patch,
        Version.build,
    }) catch unreachable;
};

pub const PLUGIN_VERSION = 11;

// STATE

const GLOBAL_STATE_VERSION = 3;

// TODO: move all the common game check stuff from plugins/modules to here; cleanup
// TODO: add index of currently consumed loaded tga IDs, since they are arbitrarily assigned
//   also, some kind of interface plugins can use to avoid clashes
//   list of stuff to update when it's made:
//     inputdisplay, practice mode vis
pub const GlobalState = extern struct {
    patch_memory: [*]u8 = undefined,
    patch_size: usize = undefined,
    patch_offset: usize = undefined,

    practice_mode: bool = false,

    hwnd: ?win.HWND = null,
    hinstance: ?win.HINSTANCE = null,

    dt_f: f32 = 0,
    fps: f32 = 0,
    fps_avg: f32 = 0,
    timestamp: u32 = 0,
    framecount: u32 = 0,

    in_race: st.ActiveState = .Off,
    player: extern struct {
        upgrades: bool = false,
        upgrades_lv: [7]u8 = undefined,
        upgrades_hp: [7]u8 = undefined,

        flags1: u32 = 0,
        in_race_count: st.ActiveState = .Off,
        in_race_results: st.ActiveState = .Off,
        in_race_racing: st.ActiveState = .Off,
        boosting: st.ActiveState = .Off,
        underheating: st.ActiveState = .On,
        overheating: st.ActiveState = .Off,
        dead: st.ActiveState = .Off,

        heat_rate: f32 = 0,
        cool_rate: f32 = 0,
        heat: f32 = 0,
    } = .{},

    fn player_reset(self: *GlobalState) void {
        const p = &self.player;
        const u: [14]u8 = mem.deref_read(&.{ 0x4D78A4, 0x0C, 0x41 }, [14]u8);
        p.upgrades_lv = u[0..7].*;
        p.upgrades_hp = u[7..14].*;
        p.upgrades = for (0..7) |i| {
            if (u[i] > 0 and u[7 + i] > 0) break true;
        } else false;

        p.flags1 = 0;
        p.in_race_count = .Off;
        p.in_race_results = .Off;
        p.in_race_racing = .Off;
        p.boosting = .Off;
        p.underheating = .On; // you start the race underheating
        p.overheating = .Off;
        p.dead = .Off;

        p.heat_rate = r.ReadPlayerValue(0x8C, f32);
        p.cool_rate = r.ReadPlayerValue(0x90, f32);
        p.heat = 0;
    }

    fn player_update(self: *GlobalState) void {
        const p = &self.player;
        p.flags1 = r.ReadPlayerValue(0x60, u32);
        p.heat = r.ReadPlayerValue(0x218, f32);
        const engine: [6]u32 = r.ReadPlayerValue(0x2A0, [6]u32);

        p.boosting.update((p.flags1 & (1 << 23)) > 0);
        p.underheating.update(p.heat >= 100);
        p.overheating.update(for (0..6) |i| {
            if (engine[i] & (1 << 3) > 0) break true;
        } else false);
        p.dead.update((p.flags1 & (1 << 14)) > 0);
        p.in_race_count.update((p.flags1 & (1 << 0)) > 0);
        p.in_race_results.update((p.flags1 & (1 << 5)) == 0);
        p.in_race_racing.update(!(p.in_race_count.on() or p.in_race_results.on()));
    }
};

pub var GLOBAL_STATE: GlobalState = .{};

pub const GLOBAL_FUNCTION_VERSION = 10;

pub const GlobalFn = extern struct {
    // Settings
    SettingGetB: *const @TypeOf(settings.get_bool) = &settings.get_bool,
    SettingGetI: *const @TypeOf(settings.get_i32) = &settings.get_i32,
    SettingGetU: *const @TypeOf(settings.get_u32) = &settings.get_u32,
    SettingGetF: *const @TypeOf(settings.get_f32) = &settings.get_f32,
    // Input
    InputGetKbDown: *const @TypeOf(input.get_kb_down) = &input.get_kb_down,
    InputGetKbUp: *const @TypeOf(input.get_kb_up) = &input.get_kb_up,
    InputGetKbPressed: *const @TypeOf(input.get_kb_pressed) = &input.get_kb_pressed,
    InputGetKbReleased: *const @TypeOf(input.get_kb_released) = &input.get_kb_released,
    //InputGetMouse: *const @TypeOf(input.get_mouse_window) = &input.get_mouse_window,
    //InputGetMouseDelta: *const @TypeOf(input.get_mouse_window_d) = &input.get_mouse_window_d,
    //InputGetMouseInWindow: *const @TypeOf(input.get_mouse_inside) = &input.get_mouse_inside,
    InputGetXInputButton: *const @TypeOf(input.get_xinput_button) = &input.get_xinput_button,
    InputGetXInputAxis: *const @TypeOf(input.get_xinput_axis) = &input.get_xinput_axis,
    // Game
    GameFreezeEnable: *const @TypeOf(Freeze.freeze) = &Freeze.freeze,
    GameFreezeDisable: *const @TypeOf(Freeze.unfreeze) = &Freeze.unfreeze,
};

pub var GLOBAL_FUNCTION: GlobalFn = .{};

// FREEZE API

// FIXME: probably want to make this request-based, to prevent plugins from
// clashing with eachother
// FIXME: also probably need to start thinking about making a distinction
// between global state and game manipulation functions
// TODO: turn off race HUD when freezing
pub const Freeze = struct {
    const pausebit: u32 = 1 << 28;
    var frozen: bool = false;
    var saved_pausebit: usize = undefined;
    var saved_pausepage: u8 = undefined;
    var saved_pausestate: u8 = undefined;
    var saved_pausescroll: f32 = undefined;

    pub fn freeze() void {
        if (frozen) return;
        const pauseflags = r.ReadEntityValue(.Jdge, 0, 0x04, u32);

        saved_pausebit = pauseflags & pausebit;
        saved_pausepage = mem.read(rc.ADDR_PAUSE_PAGE, u8);
        saved_pausestate = mem.read(rc.ADDR_PAUSE_STATE, u8);
        saved_pausescroll = mem.read(rc.ADDR_PAUSE_SCROLLINOUT, f32);

        _ = mem.write(rc.ADDR_PAUSE_PAGE, u8, 2);
        _ = mem.write(rc.ADDR_PAUSE_STATE, u8, 1);
        _ = mem.write(rc.ADDR_PAUSE_SCROLLINOUT, f32, 0);
        _ = r.WriteEntityValue(.Jdge, 0, 0x04, u32, pauseflags & ~pausebit);

        frozen = true;
    }

    pub fn unfreeze() void {
        if (!frozen) return;
        const pauseflags = r.ReadEntityValue(.Jdge, 0, 0x04, u32);

        r.WriteEntityValue(.Jdge, 0, 0x04, u32, pauseflags | saved_pausebit);
        _ = mem.write(rc.ADDR_PAUSE_SCROLLINOUT, f32, saved_pausescroll);
        _ = mem.write(rc.ADDR_PAUSE_STATE, u8, saved_pausestate);
        _ = mem.write(rc.ADDR_PAUSE_PAGE, u8, saved_pausepage);

        frozen = false;
    }
};

// UTIL

fn DrawMenuPracticeModeLabel() void {
    if (GLOBAL_STATE.practice_mode) {
        rf.swrText_CreateEntry1(640 - 20, 16, 255, 255, 255, 255, "~F0~3~s~rPractice Mode");
    }
}

fn DrawVersionString() void {
    var buf: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "~F0~s{s}", .{VersionStr}) catch return;
    rf.swrText_CreateEntry1(36, 480 - 24, 255, 255, 255, 255, &buf);
}

// INIT

pub fn init() void {
    // input-based launch toggles
    const kb_shift: i16 = w32kb.GetAsyncKeyState(@intFromEnum(w32kb.VK_SHIFT));
    const kb_shift_dn: bool = (kb_shift & KS_DOWN) != 0;
    GLOBAL_STATE.practice_mode = kb_shift_dn;

    GLOBAL_STATE.hwnd = mem.read(rc.ADDR_HWND, win.HWND);
    GLOBAL_STATE.hinstance = mem.read(rc.ADDR_HINSTANCE, win.HINSTANCE);
}

// HOOK CALLS

pub fn EarlyEngineUpdateA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    gs.in_race.update(mem.read(rc.ADDR_IN_RACE, u8) > 0);
    if (gs.in_race == .JustOn) gs.player_reset();
    if (gs.in_race.on()) gs.player_update();

    if (input.get_kb_pressed(.P) and (!(gs.in_race.on() and gs.practice_mode)))
        gs.practice_mode = !gs.practice_mode;
}

pub fn TimerUpdateA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    gs.dt_f = mem.read(rc.ADDR_TIME_FRAMETIME, f32);
    gs.fps = mem.read(rc.ADDR_TIME_FPS, f32);
    const fps_res: f32 = 1 / gs.dt_f * 2;
    gs.fps_avg = (gs.fps_avg * (fps_res - 1) + (1 / gs.dt_f)) / fps_res;
    gs.timestamp = mem.read(rc.ADDR_TIME_TIMESTAMP, u32);
    gs.framecount = mem.read(rc.ADDR_TIME_FRAMECOUNT, u32);
}

pub fn MenuTitleScreenB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    DrawVersionString();
    DrawMenuPracticeModeLabel();

    //var buf: [127:0]u8 = undefined;
    //const xa_fields = comptime std.enums.values(input.XINPUT_GAMEPAD_AXIS_INDEX);
    //for (xa_fields, 0..) |a, i| {
    //    const axis: f32 = gv.InputGetXInputAxis(a);
    //    _ = std.fmt.bufPrintZ(&buf, "~F0~s{s} {d:0<7.3}", .{ @tagName(a), axis }) catch return;
    //    rf.swrText_CreateEntry1(16, 16 + @as(u16, @truncate(i)) * 8, 255, 255, 255, 255, &buf);
    //}
    //const xb_fields = comptime std.enums.values(input.XINPUT_GAMEPAD_BUTTON_INDEX);
    //for (xb_fields, xa_fields.len..) |b, i| {
    //    const on: bool = gv.InputGetXInputButton(b).on();
    //    _ = std.fmt.bufPrintZ(&buf, "~F0~s{s} {any}", .{ @tagName(b), on }) catch return;
    //    rf.swrText_CreateEntry1(16, 16 + @as(u16, @truncate(i)) * 8, 255, 255, 255, 255, &buf);
    //}

    //const vk_fields = comptime std.enums.values(win32kb.VIRTUAL_KEY);
    //for (vk_fields) |vk| {
    //    if (gv.InputGetKbDown(vk)) {
    //        var buf: [127:0]u8 = undefined;
    //        _ = std.fmt.bufPrintZ(&buf, "~F0~s{s}", .{@tagName(vk)}) catch return;
    //        rf.swrText_CreateEntry1(16, 16, 255, 255, 255, 255, &buf);
    //        break;
    //    }
    //}
}

pub fn MenuStartRaceB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    DrawMenuPracticeModeLabel();
}

pub fn MenuRaceResultsB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    DrawMenuPracticeModeLabel();
}

pub fn MenuTrackB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    DrawMenuPracticeModeLabel();
}
