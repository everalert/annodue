const Self = @This();

const std = @import("std");
const win = std.os.windows;

const GlobalState = @import("global.zig").GlobalState;
const GlobalVTable = @import("global.zig").GlobalVTable;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");
const rc = @import("util/racer_const.zig");

const menu = @import("util/menu.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

// HUD TIMER MS

fn PatchHudTimerMs() void {
    const off_fnDrawTime3: usize = 0x450760;
    // hudDrawRaceHud
    _ = x86.call(0x460BD3, off_fnDrawTime3);
    _ = x86.call(0x460E6B, off_fnDrawTime3);
    _ = x86.call(0x460ED9, off_fnDrawTime3);
    // hudDrawRaceResults
    _ = x86.call(0x46252F, off_fnDrawTime3);
    _ = x86.call(0x462660, off_fnDrawTime3);
    _ = mem.patch_add(0x4623D7, u8, 12);
    _ = mem.patch_add(0x4623F1, u8, 12);
    _ = mem.patch_add(0x46240B, u8, 12);
    _ = mem.patch_add(0x46241E, u8, 12);
    _ = mem.patch_add(0x46242D, u8, 12);
}

// PRACTICE/STATISTICAL DATA

const race = struct {
    const stat_x: u16 = 192;
    const stat_y: u16 = 48;
    const stat_h: u8 = 12;
    const stat_col: u8 = 255;
    var total_deaths: u32 = 0;
    var total_boost_duration: f32 = 0;
    var total_boost_ratio: f32 = 0;
    var total_underheat: f32 = 0;
    var total_overheat: f32 = 0;
    var first_boost_time: f32 = 0;
    var fire_finish_duration: f32 = 0;
    var last_boost_started: f32 = 0;
    var last_boost_started_total: f32 = 0;
    var last_underheat_started: f32 = 0;
    var last_underheat_started_total: f32 = 0;
    var last_overheat_started: f32 = 0;
    var last_overheat_started_total: f32 = 0;

    fn reset() void {
        total_deaths = 0;
        total_boost_duration = 0;
        total_boost_ratio = 0;
        total_underheat = 0;
        total_overheat = 0;
        first_boost_time = 0;
        fire_finish_duration = 0;
        last_boost_started = 0;
        last_boost_started_total = 0;
        last_underheat_started = 0;
        last_underheat_started_total = 0;
        last_overheat_started = 0;
        last_overheat_started_total = 0;
    }

    fn set_last_boost_start(time: f32) void {
        last_boost_started_total = total_boost_duration;
        last_boost_started = time;
        if (first_boost_time == 0) first_boost_time = time;
    }

    fn set_total_boost(time: f32) void {
        total_boost_duration = last_boost_started_total + time - last_boost_started;
        total_boost_ratio = total_boost_duration / time;
    }

    fn set_last_underheat_start(time: f32) void {
        last_underheat_started_total = total_underheat;
        last_underheat_started = time;
    }

    fn set_total_underheat(time: f32) void {
        total_underheat = last_underheat_started_total + time - last_underheat_started;
    }

    fn set_last_overheat_start(time: f32) void {
        last_overheat_started_total = total_overheat;
        last_overheat_started = time;
    }

    fn set_total_overheat(time: f32) void {
        total_overheat = last_overheat_started_total + time - last_overheat_started;
    }

    fn set_fire_finish_duration(time: f32) void {
        fire_finish_duration = time - last_overheat_started;
    }
};

fn RenderRaceResultStat1(i: u8, label: [*:0]const u8) void {
    var buf: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "~F0~s~c{s}", .{label}) catch unreachable;
    rf.swrText_CreateEntry1(
        640 - race.stat_x,
        race.stat_y + i * race.stat_h,
        race.stat_col,
        race.stat_col,
        race.stat_col,
        255,
        &buf,
    );
}

fn RenderRaceResultStat2(i: u8, label: [*:0]const u8, value: [*:0]const u8) void {
    var buf: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "~F0~s~r{s}", .{label}) catch unreachable;
    rf.swrText_CreateEntry1(
        640 - race.stat_x - 8,
        race.stat_y + i * race.stat_h,
        race.stat_col,
        race.stat_col,
        race.stat_col,
        255,
        &buf,
    );
    _ = std.fmt.bufPrintZ(&buf, "~F0~s{s}", .{value}) catch unreachable;
    rf.swrText_CreateEntry1(
        640 - race.stat_x + 8,
        race.stat_y + i * race.stat_h,
        race.stat_col,
        race.stat_col,
        race.stat_col,
        255,
        &buf,
    );
}

fn RenderRaceResultStatU(i: u8, label: [*:0]const u8, value: u32) void {
    var buf: [23:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "{d: <7}", .{value}) catch unreachable;
    RenderRaceResultStat2(i, label, &buf);
}

fn RenderRaceResultStatF(i: u8, label: [*:0]const u8, value: f32) void {
    var buf: [23:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "{d:4.3}", .{value}) catch unreachable;
    RenderRaceResultStat2(i, label, &buf);
}

// FIXME: move the time formatting logic out of here
fn RenderRaceResultStatTime(i: u8, label: [*:0]const u8, time: f32) void {
    const t_ms: u32 = @as(u32, @intFromFloat(@round(time * 1000)));
    const sec: u32 = (t_ms / 1000);
    const ms: u32 = t_ms % 1000;
    var buf: [23:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "{d}.{d:0>3}", .{ sec, ms }) catch unreachable;
    RenderRaceResultStat2(i, label, &buf);
}

fn RenderRaceResultStatUpgrade(i: u8, cat: u8, lv: u8, hp: u8) void {
    var buf: [23:0]u8 = undefined;
    const hp_col = if (hp < 255) "~5" else "~4";
    _ = std.fmt.bufPrintZ(&buf, "{s}{d:0>3} ~1{s}", .{
        hp_col,
        hp,
        rc.UpgradeNames[cat * 6 + lv],
    }) catch unreachable;
    RenderRaceResultStat2(i, rc.UpgradeCategories[cat], &buf);
}

// TIME-BASED SPINLOCK

// TODO: only wait if inrace and unpaused?
// FIXME: check for HRT compatibility instead of trying to assign timer repeatedly
// because sleep() sucks, and timeBeginPeriod() is a bad idea
const TimeSpinlock = struct {
    const min_period: u64 = 1_000_000_000 / 500;
    const max_period: u64 = 1_000_000_000 / 10;
    var period: u64 = 1_000_000_000 / 24;
    var timer: ?std.time.Timer = null;

    fn SetPeriod(fps: u32) void {
        period = std.math.clamp(1_000_000_000 / fps, min_period, max_period);
    }

    fn Sleep() void {
        if (timer == null)
            timer = std.time.Timer.start() catch return;

        while (timer.?.read() < period)
            _ = win.kernel32.SwitchToThread();

        _ = timer.?.lap();
    }
};

// QUICK RACE MENU

// TODO: generalize menuing and add hooks to let plugins add pages to the menu
// TODO: add standard race settings (mirror, etc.)
// TODO: add convenience buttons for MU/NU
// TODO: also tracking related values for coherency, e.g. adjusting selected circuit
// TODO: make it wait till the end of the pause scroll-in, so that the scroll-out
// is always the same as a normal pause
const QuickRaceMenu = struct {
    var menu_active: bool = false;
    var initialized: bool = false;
    var gv: *GlobalVTable = undefined;

    const values = struct {
        var fps: i32 = 24;
        var vehicle: i32 = 0;
        var track: i32 = 0;
        var up_lv: [7]i32 = .{ 0, 0, 0, 0, 0, 0, 0 };
        var up_hp: [7]i32 = .{ 0, 0, 0, 0, 0, 0, 0 };
    };

    var data: menu.Menu = .{
        .title = "Quick Race",
        .confirm_text = "RACE!",
        .confirm_fn = @constCast(&@This().load_race),
        .confirm_key = .SPACE,
        .x = 64,
        .y = 64,
        .max = 11,
        .x_scroll = .{
            .scroll_time = 0.75,
            .scroll_units = 18,
            .input_dec = .LEFT,
            .input_inc = .RIGHT,
        },
        .y_scroll = .{
            .scroll_time = 0.75,
            .scroll_units = 18,
            .input_dec = .UP,
            .input_inc = .DOWN,
        },
        .items = &[_]menu.MenuItem{
            .{
                .idx = &@This().values.fps,
                .label = "FPS",
                .max = 500,
            },
            .{
                .idx = &@This().values.vehicle,
                .label = "Vehicle",
                .options = &rc.Vehicles,
                .max = rc.Vehicles.len,
            },
            .{
                .idx = &@This().values.track,
                .label = "Track",
                .options = &rc.TracksById, // FIXME: maybe change to menu order?
                .max = rc.TracksByMenu.len,
            },
            .{
                .idx = &@This().values.up_lv[0],
                .label = rc.UpgradeCategories[0],
                .options = &rc.UpgradeNames[0 * 6 .. 0 * 6 + 6].*,
                .max = 6,
                .wrap = false,
            },
            .{
                .idx = &@This().values.up_lv[1],
                .label = rc.UpgradeCategories[1],
                .options = &rc.UpgradeNames[1 * 6 .. 1 * 6 + 6].*,
                .max = 6,
                .wrap = false,
            },
            .{
                .idx = &@This().values.up_lv[2],
                .label = rc.UpgradeCategories[2],
                .options = &rc.UpgradeNames[2 * 6 .. 2 * 6 + 6].*,
                .max = 6,
                .wrap = false,
            },
            .{
                .idx = &@This().values.up_lv[3],
                .label = rc.UpgradeCategories[3],
                .options = &rc.UpgradeNames[3 * 6 .. 3 * 6 + 6].*,
                .max = 6,
                .wrap = false,
            },
            .{
                .idx = &@This().values.up_lv[4],
                .label = rc.UpgradeCategories[4],
                .options = &rc.UpgradeNames[4 * 6 .. 4 * 6 + 6].*,
                .max = 6,
                .wrap = false,
            },
            .{
                .idx = &@This().values.up_lv[5],
                .label = rc.UpgradeCategories[5],
                .options = &rc.UpgradeNames[5 * 6 .. 5 * 6 + 6].*,
                .max = 6,
                .wrap = false,
            },
            .{
                .idx = &@This().values.up_lv[6],
                .label = rc.UpgradeCategories[6],
                .options = &rc.UpgradeNames[6 * 6 .. 6 * 6 + 6].*,
                .max = 6,
                .wrap = false,
            },
        },
    };

    fn load_race() void {
        TimeSpinlock.SetPeriod(@intCast(values.fps));
        r.WriteEntityValue(.Hang, 0, 0x73, u8, @as(u8, @intCast(values.vehicle)));
        r.WriteEntityValue(.Hang, 0, 0x5D, u8, @as(u8, @intCast(values.track)));
        const u = mem.deref(&.{ 0x4D78A4, 0x0C, 0x41 });
        for (values.up_lv, values.up_hp, 0..) |lv, hp, i| {
            _ = mem.write(u + 0 + i, u8, @as(u8, @intCast(lv)));
            _ = mem.write(u + 7 + i, u8, @as(u8, @intCast(hp)));
        }

        const jdge: usize = mem.deref_read(&.{
            rc.ADDR_ENTITY_MANAGER_JUMPTABLE,
            @intFromEnum(rc.ENTITY.Jdge) * 4,
            0x10,
        }, usize);
        rf.TriggerLoad_InRace(jdge, rc.MAGIC_RSTR);
        close();
    }

    fn init() void {
        if (initialized) return;

        values.vehicle = r.ReadEntityValue(.Hang, 0, 0x73, u8);
        values.track = r.ReadEntityValue(.Hang, 0, 0x5D, u8);
        const u: [14]u8 = mem.deref_read(&.{ 0x4D78A4, 0x0C, 0x41 }, [14]u8);
        for (u[0..7], u[7..14], 0..) |lv, hp, i| {
            values.up_lv[i] = lv;
            values.up_hp[i] = hp;
        }

        initialized = true;
    }

    fn open() void {
        gv.GameFreezeEnable();
        data.idx = 0;
        menu_active = true;
    }

    fn close() void {
        gv.GameFreezeDisable();
        _ = mem.write(rc.ADDR_PAUSE_STATE, u8, 3);
        menu_active = false;
    }

    fn update() void {
        init();

        const pausestate: u8 = mem.read(rc.ADDR_PAUSE_STATE, u8);
        if (menu_active and gv.InputGetKbPressed(.ESCAPE)) {
            close();
        } else if (pausestate == 2 and gv.InputGetKbPressed(.ESCAPE)) {
            open();
        }

        if (menu_active) data.UpdateAndDrawEx(
            gv.InputGetKbPressed,
            gv.InputGetKbReleased,
            gv.InputGetKbDown,
        );
    }
};

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return "QualityOfLife";
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return "0.0.1";
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;
    if (gv.SettingGetB("general", "ms_timer_enable").?) {
        PatchHudTimerMs();
    }

    QuickRaceMenu.gv = gv;
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;
    const def_laps: u32 = gv.SettingGetU("general", "default_laps") orelse 3;
    if (def_laps >= 1 and def_laps <= 5) {
        const laps: usize = mem.deref(&.{ 0x4BFDB8, 0x8F });
        _ = mem.write(laps, u8, @as(u8, @truncate(def_laps)));
    }
    const def_racers: u32 = gv.SettingGetU("general", "default_racers") orelse 12;
    if (def_racers >= 1 and def_racers <= 12) {
        const addr_racers: usize = 0x50C558;
        _ = mem.write(addr_racers, u8, @as(u8, @truncate(def_racers)));
    }
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

// HOOKS

// FIXME: implement fps cap into settings at some point; had issues with hash
// clashing (i think) in initial impl
export fn TimerUpdateB(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = gs;
    _ = initialized;

    TimeSpinlock.Sleep();
}

// FIXME: settings toggles for both of these
// FIXME: probably want this mid-engine update, immediately before Jdge gets processed?
export fn EarlyEngineUpdateB(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = initialized;
    // Quick Reload
    if (gs.in_race.isOn() and gv.InputGetKbDown(.@"2") and gv.InputGetKbPressed(.ESCAPE)) {
        const jdge: usize = mem.deref_read(&.{
            rc.ADDR_ENTITY_MANAGER_JUMPTABLE,
            @intFromEnum(rc.ENTITY.Jdge) * 4,
            0x10,
        }, usize);
        rf.TriggerLoad_InRace(jdge, rc.MAGIC_RSTR);
    }

    // Quick Race Menu
    if (gs.in_race.isOn() and !gs.player.in_race_results.isOn())
        QuickRaceMenu.update();
}

export fn TextRenderB(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = initialized;
    if (!gv.SettingGetB("practice", "practice_tool_enable").?) return;

    if (gs.in_race.isOn()) {
        if (gs.in_race == .JustOn) race.reset();
        var buf: [127:0]u8 = undefined;

        const race_times: [6]f32 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x60 }, [6]f32);
        const total_time: f32 = race_times[5];

        if (gs.player.in_race_count.isOn()) {
            if (gs.player.in_race_count == .JustOn) {
                // ...
            }
        } else if (gs.player.in_race_results.isOn()) {
            // FIXME: final stat calculation is slightly off, seems to be up to
            // a frame early now (since porting to plugin dlls).
            if (gs.player.in_race_results == .JustOn) {
                if (gs.player.boosting == .JustOff) race.set_total_boost(total_time);
                if (gs.player.underheating == .JustOff) race.set_total_underheat(total_time);
                if (gs.player.overheating == .JustOff) {
                    race.set_fire_finish_duration(total_time);
                    race.set_total_overheat(total_time);
                }
            }

            _ = std.fmt.bufPrintZ(
                &buf,
                "{d:>2.0}/{s}",
                .{ gs.fps_avg, rc.UpgradeNames[gs.player.upgrades_lv[0]] },
            ) catch unreachable;
            RenderRaceResultStat1(0, &buf);

            const upg_prefix = if (gs.player.upgrades) "" else "NO ";
            _ = std.fmt.bufPrintZ(&buf, "{s}Upgrades", .{upg_prefix}) catch unreachable;
            RenderRaceResultStat1(1, &buf);

            for (0..7) |i| RenderRaceResultStatUpgrade(
                3 + @as(u8, @truncate(i)),
                @as(u8, @truncate(i)),
                gs.player.upgrades_lv[i],
                gs.player.upgrades_hp[i],
            );

            RenderRaceResultStatU(11, "Deaths", race.total_deaths);
            RenderRaceResultStatTime(12, "Boost Time", race.total_boost_duration);
            RenderRaceResultStatF(13, "Boost Ratio", race.total_boost_ratio);
            RenderRaceResultStatTime(14, "First Boost", race.first_boost_time);
            RenderRaceResultStatTime(15, "Underheat Time", race.total_underheat);
            RenderRaceResultStatTime(16, "Fire Finish", race.fire_finish_duration);
            RenderRaceResultStatTime(17, "Overheat Time", race.total_overheat);
        } else {
            if (gs.player.dead == .JustOn) race.total_deaths += 1;

            if (gs.player.boosting == .JustOn) race.set_last_boost_start(total_time);
            if (gs.player.boosting.isOn()) race.set_total_boost(total_time);
            if (gs.player.boosting == .JustOff) race.set_total_boost(total_time);

            if (gs.player.underheating == .JustOn) race.set_last_underheat_start(total_time);
            if (gs.player.underheating.isOn()) race.set_total_underheat(total_time);
            if (gs.player.underheating == .JustOff) race.set_total_underheat(total_time);

            if (gs.player.overheating == .JustOn) race.set_last_overheat_start(total_time);
            if (gs.player.overheating.isOn()) race.set_total_overheat(total_time);
            if (gs.player.overheating == .JustOff) race.set_total_overheat(total_time);
        }
    }
}
