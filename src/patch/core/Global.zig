const Self = @This();

const std = @import("std");
const win = std.os.windows;

const freeze = @import("Freeze.zig");
const toast = @import("Toast.zig");
const input = @import("Input.zig");
const settings = @import("Settings.zig");
const s = settings.SettingsState;

const st = @import("../util/active_state.zig");
const xinput = @import("../util/xinput.zig");
const dbg = @import("../util/debug.zig");
const msg = @import("../util/message.zig");
const mem = @import("../util/memory.zig");
const r = @import("../util/racer.zig");
const rf = r.functions;
const rc = r.constants;
const rt = r.text;
const rto = rt.TextStyleOpts;

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;
const w32xc = w32.ui.input.xbox_controller;
const w32wm = w32.ui.windows_and_messaging;
const KS_DOWN: i16 = -1;
const KS_PRESSED: i16 = 1; // since last call

// NOTE: may want to figure out all the code caves in .data for potential use
// TODO: split up the versioning, global structs, etc. from the business logic

// VERSION

// NOTE: current minver for updates: 0.1.2
// TODO: include tag when appropriate
pub const Version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 4,
    .pre = "alpha",
    .build = "270",
};

// TODO: use SemanticVersion parse fn instead
pub const VersionStr: [:0]u8 = s: {
    var buf: [127:0]u8 = undefined;
    break :s std.fmt.bufPrintZ(&buf, "Annodue {d}.{d}.{d}.{s}", .{
        Version.major,
        Version.minor,
        Version.patch,
        Version.build.?,
    }) catch unreachable; // comptime
};

pub const PLUGIN_VERSION = 18;

// STATE

const RaceState = enum(u8) { None, PreRace, Countdown, Racing, PostRace, PostRaceExiting };

const GLOBAL_STATE_VERSION = 4;

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

    hwnd: ?win.HWND = null,
    hinstance: ?win.HINSTANCE = null,

    dt_f: f32 = 0,
    fps: f32 = 0,
    fps_avg: f32 = 0,
    timestamp: u32 = 0,
    framecount: u32 = 0,

    in_race: st.ActiveState = .Off,
    race_state: RaceState = .None,
    race_state_prev: RaceState = .None,
    race_state_new: bool = false,
    player: extern struct {
        upgrades: bool = false,
        upgrades_lv: [7]u8 = undefined,
        upgrades_hp: [7]u8 = undefined,

        flags1: u32 = 0,
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
    }
};

pub var GLOBAL_STATE: GlobalState = .{};

pub const GLOBAL_FUNCTION_VERSION = 15;

pub const GlobalFunction = extern struct {
    // Settings
    SettingGetB: *const @TypeOf(settings.get_bool) = &settings.get_bool,
    SettingGetI: *const @TypeOf(settings.get_i32) = &settings.get_i32,
    SettingGetU: *const @TypeOf(settings.get_u32) = &settings.get_u32,
    SettingGetF: *const @TypeOf(settings.get_f32) = &settings.get_f32,
    // Input
    InputGetKb: *const @TypeOf(input.get_kb) = &input.get_kb,
    InputGetKbRaw: *const @TypeOf(input.get_kb_raw) = &input.get_kb_raw,
    InputGetMouse: *const @TypeOf(input.get_mouse_raw) = &input.get_mouse_raw,
    InputGetMouseDelta: *const @TypeOf(input.get_mouse_raw_d) = &input.get_mouse_raw_d,
    InputLockMouse: *const @TypeOf(input.lock_mouse) = &input.lock_mouse,
    //InputGetMouseInWindow: *const @TypeOf(input.get_mouse_inside) = &input.get_mouse_inside,
    InputGetXInputButton: *const @TypeOf(input.get_xinput_button) = &input.get_xinput_button,
    InputGetXInputAxis: *const @TypeOf(input.get_xinput_axis) = &input.get_xinput_axis,
    // Game
    GameFreezeEnable: *const @TypeOf(freeze.Freeze.freeze) = &freeze.Freeze.freeze,
    GameFreezeDisable: *const @TypeOf(freeze.Freeze.unfreeze) = &freeze.Freeze.unfreeze,
    GameFreezeIsFrozen: *const @TypeOf(freeze.Freeze.is_frozen) = &freeze.Freeze.is_frozen,
    // Toast
    ToastNew: *const @TypeOf(toast.ToastSystem.NewToast) = &toast.ToastSystem.NewToast,
};

pub var GLOBAL_FUNCTION: GlobalFunction = .{};

// UTIL

const style_practice_label = rt.MakeTextHeadStyle(.Default, true, .Yellow, .Right, .{rto.ToggleShadow}) catch "";

fn DrawMenuPracticeModeLabel() void {
    if (GLOBAL_STATE.practice_mode) {
        rt.DrawText(640 - 20, 16, "Practice Mode", .{}, 0xFFFFFFFF, style_practice_label) catch {};
    }
}

fn DrawVersionString() void {
    rt.DrawText(36, 480 - 24, "{s}", .{VersionStr}, 0xFFFFFFFF, null) catch {};
}

// INIT

pub fn init() bool {
    const kb_shift: i16 = w32kb.GetAsyncKeyState(@intFromEnum(w32kb.VK_SHIFT));
    const kb_shift_dn: bool = (kb_shift & KS_DOWN) != 0;
    if (kb_shift_dn)
        return false;

    GLOBAL_STATE.hwnd = mem.read(rc.ADDR_HWND, win.HWND);
    GLOBAL_STATE.hinstance = mem.read(rc.ADDR_HINSTANCE, win.HINSTANCE);

    return true;
}

// HOOK CALLS

pub fn OnInitLate(gs: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    gs.init_late_passed = true;
}

pub fn EngineUpdateStage14A(gs: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    const player_ready: bool = mem.read(rc.RACE_DATA_PLAYER_RACE_DATA_PTR_ADDR, u32) != 0 and
        r.ReadRaceDataValue(0x84, u32) != 0;
    gs.in_race.update(player_ready);

    if (gs.in_race == .JustOn) gs.player_reset();
    if (gs.in_race.on()) gs.player_update();

    gs.race_state_prev = gs.race_state;
    gs.race_state = blk: {
        if (!gs.in_race.on()) break :blk .None;
        if (mem.read(rc.ADDR_IN_RACE, u8) == 0) break :blk .PreRace;
        const countdown: bool = gs.player.flags1 & (1 << 0) != 0;
        if (countdown) break :blk .Countdown;
        const postrace: bool = gs.player.flags1 & (1 << 5) == 0;
        const show_stats: bool = r.ReadEntityValue(.Jdge, 0, 0x08, u32) & 0x0F == 2;
        if (postrace and show_stats) break :blk .PostRace;
        if (postrace) break :blk .PostRaceExiting;
        break :blk .Racing;
    };
    gs.race_state_new = gs.race_state == gs.race_state_prev;
}

pub fn TimerUpdateA(gs: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    gs.dt_f = mem.read(rc.ADDR_TIME_FRAMETIME, f32);
    gs.fps = mem.read(rc.ADDR_TIME_FPS, f32);
    const fps_res: f32 = 1 / gs.dt_f * 2;
    gs.fps_avg = (gs.fps_avg * (fps_res - 1) + (1 / gs.dt_f)) / fps_res;
    gs.timestamp = mem.read(rc.ADDR_TIME_TIMESTAMP, u32);
    gs.framecount = mem.read(rc.ADDR_TIME_FRAMECOUNT, u32);
}

pub fn MenuTitleScreenB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    // TODO: make text only appear on the actual title screen, i.e. remove from file select etc.
    DrawVersionString();
    DrawMenuPracticeModeLabel();

    //var buf: [127:0]u8 = undefined;
    //const xa_fields = comptime std.enums.values(input.XINPUT_GAMEPAD_AXIS_INDEX);
    //for (xa_fields, 0..) |a, i| {
    //    const axis: f32 = gv.InputGetXInputAxis(a);
    //    _ = std.fmt.bufPrintZ(&buf, "~F0~s{s} {d:0<7.3}", .{ @tagName(a), axis }) catch return;
    //    rt.DrawText(16, 16 + @as(u16, @truncate(i)) * 8, 255, 255, 255, 255, &buf);
    //}
    //const xb_fields = comptime std.enums.values(input.XINPUT_GAMEPAD_BUTTON_INDEX);
    //for (xb_fields, xa_fields.len..) |b, i| {
    //    const on: bool = gv.InputGetXInputButton(b).on();
    //    _ = std.fmt.bufPrintZ(&buf, "~F0~s{s} {any}", .{ @tagName(b), on }) catch return;
    //    rt.DrawText(16, 16 + @as(u16, @truncate(i)) * 8, 255, 255, 255, 255, &buf);
    //}

    //const vk_fields = comptime std.enums.values(win32kb.VIRTUAL_KEY);
    //for (vk_fields) |vk| {
    //    if (gv.InputGetKbDown(vk)) {
    //        var buf: [127:0]u8 = undefined;
    //        _ = std.fmt.bufPrintZ(&buf, "~F0~s{s}", .{@tagName(vk)}) catch return;
    //        rt.DrawText(16, 16, 255, 255, 255, 255, &buf);
    //        break;
    //    }
    //}
}

pub fn MenuStartRaceB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuRaceResultsB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuTrackSelectB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuTrackB(_: *GlobalState, _: *GlobalFunction) callconv(.C) void {
    DrawMenuPracticeModeLabel();
}
