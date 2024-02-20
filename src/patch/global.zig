const Self = @This();

const std = @import("std");
const win = std.os.windows;

const settings = @import("settings.zig");
const s = settings.state;

const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");

const win32 = @import("import/import.zig").win32;
const win32kb = win32.ui.input.keyboard_and_mouse;
const win32wm = win32.ui.windows_and_messaging;
const KS_DOWN: i16 = -1;
const KS_PRESSED: i16 = 1; // since last call

// VERSION

const VersionTag = enum(u32) {
    None,
    Alpha,
    Beta,
    ReleaseCandidate,
};

pub const Version = struct {
    pub const major: u32 = 0;
    pub const minor: u32 = 0;
    pub const patch: u32 = 1;
    pub const tag_type: VersionTag = .None;
    pub const tag_no: u32 = 0;
    pub const build: u32 = 76; // based on git commits
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

// STATE

const ActiveState = enum(u8) {
    Off = 0,
    On = 1,
    JustOff = 2,
    JustOn = 3,

    pub fn isOn(self: *ActiveState) bool {
        return (@intFromEnum(self.*) & 1) > 0;
    }

    pub fn update(self: *ActiveState, on: bool) void {
        const new: u8 = @intFromBool(on);
        const changed: u8 = (new ^ @intFromBool(self.isOn())) << 1;
        self.* = @enumFromInt(new | changed);
    }
};

const GLOBAL_STATE_VERSION = 0;

// TODO: move all the common game check stuff from plugins/modules to here; cleanup
pub const GlobalState = extern struct {
    pub var practice_mode: bool = false;

    pub var hwnd: ?win.HWND = null;
    pub var hinstance: ?win.HINSTANCE = null;

    pub var dt_f: f32 = 0;
    pub var fps: f32 = 0;
    pub var fps_avg: f32 = 0;
    pub var timestamp: u32 = 0;
    pub var framecount: u32 = 0;

    pub var in_race: ActiveState = .Off;
    pub const player = extern struct {
        pub var upgrades: bool = false;
        pub var upgrades_lv: [7]u8 = undefined;
        pub var upgrades_hp: [7]u8 = undefined;

        pub var flags1: u32 = 0;
        pub var in_race_count: ActiveState = .Off;
        pub var in_race_results: ActiveState = .Off;
        pub var in_race_racing: ActiveState = .Off;
        pub var boosting: ActiveState = .Off;
        pub var underheating: ActiveState = .On;
        pub var overheating: ActiveState = .Off;
        pub var dead: ActiveState = .Off;

        pub var heat_rate: f32 = 0;
        pub var cool_rate: f32 = 0;
        pub var heat: f32 = 0;

        fn reset() void {
            const u: [14]u8 = mem.deref_read(&.{ 0x4D78A4, 0x0C, 0x41 }, [14]u8);
            upgrades_lv = u[0..7].*;
            upgrades_hp = u[7..14].*;
            upgrades = for (0..7) |i| {
                if (u[i] > 0 and u[7 + i] > 0) break true;
            } else false;

            flags1 = 0;
            in_race_count = .Off;
            in_race_results = .Off;
            in_race_racing = .Off;
            boosting = .Off;
            underheating = .On; // you start the race underheating
            overheating = .Off;
            dead = .Off;

            heat_rate = r.ReadPlayerValue(0x8C, f32);
            cool_rate = r.ReadPlayerValue(0x90, f32);
            heat = 0;
        }

        fn update() void {
            flags1 = r.ReadPlayerValue(0x60, u32);
            heat = r.ReadPlayerValue(0x218, f32);
            const engine: [6]u32 = r.ReadPlayerValue(0x2A0, [6]u32);

            boosting.update((flags1 & (1 << 23)) > 0);
            underheating.update(heat >= 100);
            overheating.update(for (0..6) |i| {
                if (engine[i] & (1 << 3) > 0) break true;
            } else false);
            dead.update((flags1 & (1 << 14)) > 0);
            in_race_count.update((flags1 & (1 << 0)) > 0);
            in_race_results.update((flags1 & (1 << 5)) == 0);
            in_race_racing.update(!(in_race_count.isOn() or in_race_results.isOn()));
        }
    };
};

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
    if (GlobalState.practice_mode) {
        rf.swrText_CreateEntry1(640 - 20, 16, 255, 255, 255, 255, "~F0~3~s~rPractice Mode");
    }
}

fn DrawVersionString() void {
    var buf: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "~F0~s{s}", .{VersionStr}) catch return;
    rf.swrText_CreateEntry1(36, 480 - 24, 255, 255, 255, 255, &buf);
}

// INIT

pub fn init(alloc: std.mem.Allocator, memory: usize) usize {
    _ = alloc;

    // input-based launch toggles
    const kb_shift: i16 = win32kb.GetAsyncKeyState(@intFromEnum(win32kb.VK_SHIFT));
    const kb_shift_dn: bool = (kb_shift & KS_DOWN) != 0;
    GlobalState.practice_mode = kb_shift_dn;

    GlobalState.hwnd = mem.read(rc.ADDR_HWND, win.HWND);
    GlobalState.hinstance = mem.read(rc.ADDR_HINSTANCE, win.HINSTANCE);

    return memory;
}

// HOOK CALLS

pub fn EarlyEngineUpdate_After() void {
    GlobalState.in_race.update(mem.read(rc.ADDR_IN_RACE, u8) > 0);
    if (GlobalState.in_race == .JustOn) GlobalState.player.reset();
    if (GlobalState.in_race.isOn()) GlobalState.player.update();

    if (input.get_kb_pressed(.P) and (!(GlobalState.in_race.isOn() and GlobalState.practice_mode)))
        GlobalState.practice_mode = !GlobalState.practice_mode;
}

pub fn TimerUpdate_After() void {
    GlobalState.dt_f = mem.read(rc.ADDR_TIME_FRAMETIME, f32);
    GlobalState.fps = mem.read(rc.ADDR_TIME_FPS, f32);
    const fps_res: f32 = 1 / GlobalState.dt_f * 2;
    GlobalState.fps_avg = (GlobalState.fps_avg * (fps_res - 1) + (1 / GlobalState.dt_f)) / fps_res;
    GlobalState.timestamp = mem.read(rc.ADDR_TIME_TIMESTAMP, u32);
    GlobalState.framecount = mem.read(rc.ADDR_TIME_FRAMECOUNT, u32);
}

pub fn MenuTitleScreen_Before() void {
    DrawVersionString();
    DrawMenuPracticeModeLabel();
}

pub fn MenuStartRace_Before() void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuRaceResults_Before() void {
    DrawMenuPracticeModeLabel();
}

pub fn MenuTrack_Before() void {
    DrawMenuPracticeModeLabel();
}
