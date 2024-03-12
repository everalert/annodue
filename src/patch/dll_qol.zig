const Self = @This();

const std = @import("std");
const win = std.os.windows;
const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;

const GlobalState = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFn;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const st = @import("util/active_state.zig");
const r = @import("util/racer.zig");
const rf = r.functions;
const rc = r.constants;
const rt = r.text;
const rto = rt.TextStyleOpts;

const timing = @import("util/timing.zig");
const menu = @import("util/menu.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

// TODO: figure out wtf to do to manage state through hot-reload etc.

// HUD TIMER MS

const end_race_timer_offset: u8 = 12;

fn PatchHudTimerMs() void {
    // hudDrawRaceHud
    _ = x86.call(0x460BD3, @intFromPtr(rf.swrText_DrawTime3));
    _ = x86.call(0x460E6B, @intFromPtr(rf.swrText_DrawTime3));
    _ = x86.call(0x460ED9, @intFromPtr(rf.swrText_DrawTime3));
    // hudDrawRaceResults
    _ = x86.call(0x46252F, @intFromPtr(rf.swrText_DrawTime3));
    _ = x86.call(0x462660, @intFromPtr(rf.swrText_DrawTime3));
    _ = mem.write(0x4623D7, u8, comptime end_race_timer_offset + 91); // 91
    _ = mem.write(0x4623F1, u8, comptime end_race_timer_offset + 105); // 105
    _ = mem.write(0x46240B, u8, comptime end_race_timer_offset + 115); // 115
    _ = mem.write(0x46241E, u8, comptime end_race_timer_offset + 125); // 125
    _ = mem.write(0x46242D, u8, comptime end_race_timer_offset + 135); // 135
}

// PRACTICE/STATISTICAL DATA

const race = struct {
    const stat_x: i16 = 192;
    const stat_y: i16 = 48;
    const stat_h: u8 = 12;
    const stat_col: ?u32 = 0xFFFFFFFF;
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

const s_head = rt.MakeTextHeadStyle(.Default, true, null, .Center, .{rto.ToggleShadow}) catch "";

fn RenderRaceResultHeader(i: u8, comptime fmt: []const u8, args: anytype) void {
    rt.DrawText(640 - race.stat_x, race.stat_y + i * race.stat_h, fmt, args, race.stat_col, s_head) catch {};
}

const s_stat = rt.MakeTextHeadStyle(.Default, true, null, .Right, .{rto.ToggleShadow}) catch "";

fn RenderRaceResultStat(i: u8, label: []const u8, comptime value_fmt: []const u8, value_args: anytype) void {
    rt.DrawText(640 - race.stat_x - 8, race.stat_y + i * race.stat_h, "{s}", .{label}, race.stat_col, s_stat) catch {};
    rt.DrawText(640 - race.stat_x + 8, race.stat_y + i * race.stat_h, value_fmt, value_args, race.stat_col, null) catch {};
}

fn RenderRaceResultStatU(i: u8, label: []const u8, value: u32) void {
    RenderRaceResultStat(i, label, "{d: <7}", .{value});
}

fn RenderRaceResultStatF(i: u8, label: []const u8, value: f32) void {
    RenderRaceResultStat(i, label, "{d:4.3}", .{value});
}

fn RenderRaceResultStatTime(i: u8, label: []const u8, time: f32) void {
    const t = timing.RaceTimeFromFloat(time);
    RenderRaceResultStat(i, label, "{d}:{d:0>2}.{d:0>3}", .{ t.min, t.sec, t.ms });
}

const s_upg_full = rt.MakeTextStyle(.Green, null, .{}) catch "";
const s_upg_dmg = rt.MakeTextStyle(.Red, null, .{}) catch "";

fn RenderRaceResultStatUpgrade(i: u8, cat: u8, lv: u8, hp: u8) void {
    RenderRaceResultStat(i, rc.UpgradeCategories[cat], "{s}{d:0>3} ~1{s}", .{
        if (hp < 255) s_upg_dmg else s_upg_full,
        hp,
        rc.UpgradeNames[cat * 6 + lv],
    });
}

// QUICK RACE MENU

// TODO: generalize menuing and add hooks to let plugins add pages to the menu
// TODO: add convenience buttons for MU/NU
// TODO: also track related values for coherency
//  - adjusting selected circuit in menus after switching
//  - changing the selected stuff in quick race menu to match loaded stuff,
//    i.e. so that it always opens with the current settings even if you dont load via quickrace
// TODO: make it wait till the end of the pause scroll-in, so that the scroll-out
// is always the same as a normal pause
// TODO: add options/differentiation for tournament mode races, and also maybe
// set the global 'in tournament mode' accordingly
const QuickRaceMenu = extern struct {
    const menu_key: [*:0]const u8 = "QuickRaceMenu";
    var menu_active: bool = false;
    var initialized: bool = false;
    var gv: *GlobalFn = undefined;

    var FpsTimer: timing.TimeSpinlock = .{};

    const values = struct {
        var fps: i32 = 24;
        var vehicle: i32 = 0;
        var track: i32 = 0;
        var up_lv: [7]i32 = .{ 0, 0, 0, 0, 0, 0, 0 };
        var up_hp: [7]i32 = .{ 0, 0, 0, 0, 0, 0, 0 };
        var mirror: i32 = 0; // hang
        var laps: i32 = 1; // hang, 1-5
        var racers: i32 = 1; // 0x50C558, 1-12 normally, up to 20 without crash?
        var ai_speed: i32 = 2; // hang, 1-3
        //var winnings_split: i32 = 1; // hang
    };

    var input_confirm_state: st.ActiveState = undefined;
    var input_x_dec_state: st.ActiveState = undefined;
    var input_x_inc_state: st.ActiveState = undefined;
    var input_y_dec_state: st.ActiveState = undefined;
    var input_y_inc_state: st.ActiveState = undefined;
    var input_confirm: w32kb.VIRTUAL_KEY = .SPACE;
    var input_x_dec: w32kb.VIRTUAL_KEY = .LEFT;
    var input_x_inc: w32kb.VIRTUAL_KEY = .RIGHT;
    var input_y_dec: w32kb.VIRTUAL_KEY = .UP;
    var input_y_inc: w32kb.VIRTUAL_KEY = .DOWN;
    fn get_input_confirm(i: st.ActiveState) callconv(.C) bool {
        return input_confirm_state == i;
    }
    fn get_input_x_dec(i: st.ActiveState) callconv(.C) bool {
        return input_x_dec_state == i;
    }
    fn get_input_x_inc(i: st.ActiveState) callconv(.C) bool {
        return input_x_inc_state == i;
    }
    fn get_input_y_dec(i: st.ActiveState) callconv(.C) bool {
        return input_y_dec_state == i;
    }
    fn get_input_y_inc(i: st.ActiveState) callconv(.C) bool {
        return input_y_inc_state == i;
    }

    var data: menu.Menu = .{
        .title = "Quick Race",
        .confirm_text = "RACE!",
        .confirm_fn = @constCast(&load_race),
        .confirm_key = get_input_confirm,
        .max = QuickRaceMenuItems.len + 1,
        .x_scroll = .{
            .scroll_time = 0.75,
            .scroll_units = 18,
            .input_dec = get_input_x_dec,
            .input_inc = get_input_x_inc,
        },
        .y_scroll = .{
            .scroll_time = 0.75,
            .scroll_units = 18,
            .input_dec = get_input_y_dec,
            .input_inc = get_input_y_inc,
        },
        .items = &QuickRaceMenuItems,
    };

    fn load_race() void {
        FpsTimer.SetPeriod(@intCast(values.fps));
        r.WriteEntityValue(.Hang, 0, 0x73, u8, @as(u8, @intCast(values.vehicle)));
        r.WriteEntityValue(.Hang, 0, 0x5D, u8, @as(u8, @intCast(values.track)));
        r.WriteEntityValue(.Hang, 0, 0x6E, u8, @as(u8, @intCast(values.mirror)));
        r.WriteEntityValue(.Hang, 0, 0x8F, u8, @as(u8, @intCast(values.laps)));
        r.WriteEntityValue(.Hang, 0, 0x72, u8, @as(u8, @intCast(values.racers))); // also: 0x50C558
        r.WriteEntityValue(.Hang, 0, 0x90, u8, @as(u8, @intCast(values.ai_speed)));
        //r.WriteEntityValue(.Hang, 0, 0x91, u8, @as(u8, @intCast(values.winnings_split)));
        const u = mem.deref(&.{ rc.ADDR_RACE_DATA, 0x0C, 0x41 });
        for (values.up_lv, values.up_hp, 0..) |lv, hp, i| {
            _ = mem.write(u + 0 + i, u8, @as(u8, @intCast(lv)));
            _ = mem.write(u + 7 + i, u8, @as(u8, @intCast(hp)));
        }

        const jdge = r.DerefEntity(.Jdge, 0, 0);
        rf.TriggerLoad_InRace(jdge, rc.MAGIC_RSTR);
        close();
    }

    fn init() void {
        if (initialized) return;

        values.vehicle = r.ReadEntityValue(.Hang, 0, 0x73, u8);
        values.track = r.ReadEntityValue(.Hang, 0, 0x5D, u8);
        values.mirror = r.ReadEntityValue(.Hang, 0, 0x6E, u8);
        values.laps = r.ReadEntityValue(.Hang, 0, 0x8F, u8);
        values.racers = r.ReadEntityValue(.Hang, 0, 0x72, u8); // also: 0x50C558
        values.ai_speed = r.ReadEntityValue(.Hang, 0, 0x90, u8);
        //values.winnings_split = r.ReadEntityValue(.Hang, 0, 0x91, u8);
        const u: [14]u8 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x0C, 0x41 }, [14]u8);
        for (u[0..7], u[7..14], 0..) |lv, hp, i| {
            values.up_lv[i] = lv;
            values.up_hp[i] = hp;
        }

        initialized = true;
    }

    fn open() void {
        if (!gv.GameFreezeEnable(menu_key)) return;
        data.idx = 0;
        menu_active = true;
    }

    fn close() void {
        if (!gv.GameFreezeDisable(menu_key)) return;
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

        if (menu_active) data.UpdateAndDrawEx();
    }
};

const QuickRaceMenuItems = [_]menu.MenuItem{
    menu.MenuItemRange(&QuickRaceMenu.values.fps, "FPS", 10, 500, true),
    menu.MenuItemList(&QuickRaceMenu.values.vehicle, "Vehicle", &rc.Vehicles, true),
    // FIXME: maybe change to menu order?
    menu.MenuItemList(&QuickRaceMenu.values.track, "Track", &rc.TracksById, true),
    menu.MenuItemList(&QuickRaceMenu.values.up_lv[0], rc.UpgradeCategories[0], &rc.UpgradeNames[0 * 6 .. 0 * 6 + 6].*, false),
    menu.MenuItemList(&QuickRaceMenu.values.up_lv[1], rc.UpgradeCategories[1], &rc.UpgradeNames[1 * 6 .. 1 * 6 + 6].*, false),
    menu.MenuItemList(&QuickRaceMenu.values.up_lv[2], rc.UpgradeCategories[2], &rc.UpgradeNames[2 * 6 .. 2 * 6 + 6].*, false),
    menu.MenuItemList(&QuickRaceMenu.values.up_lv[3], rc.UpgradeCategories[3], &rc.UpgradeNames[3 * 6 .. 3 * 6 + 6].*, false),
    menu.MenuItemList(&QuickRaceMenu.values.up_lv[4], rc.UpgradeCategories[4], &rc.UpgradeNames[4 * 6 .. 4 * 6 + 6].*, false),
    menu.MenuItemList(&QuickRaceMenu.values.up_lv[5], rc.UpgradeCategories[5], &rc.UpgradeNames[5 * 6 .. 5 * 6 + 6].*, false),
    menu.MenuItemList(&QuickRaceMenu.values.up_lv[6], rc.UpgradeCategories[6], &rc.UpgradeNames[6 * 6 .. 6 * 6 + 6].*, false),
    menu.MenuItemToggle(&QuickRaceMenu.values.mirror, "Mirror"),
    menu.MenuItemRange(&QuickRaceMenu.values.laps, "Laps", 1, 5, true),
    menu.MenuItemRange(&QuickRaceMenu.values.racers, "Racers", 1, 12, true),
    menu.MenuItemList(&QuickRaceMenu.values.ai_speed, "AI Speed", &[_][]const u8{
        "Slow", "Average", "Fast",
    }, true),
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

export fn OnInit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;
    if (gv.SettingGetB("general", "ms_timer_enable").?)
        PatchHudTimerMs();

    QuickRaceMenu.gv = gv;
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;

    const def_laps: u32 = gv.SettingGetU("general", "default_laps") orelse 3;
    if (def_laps >= 1 and def_laps <= 5)
        r.WriteEntityValue(.Hang, 0, 0x8F, u8, @as(u8, @truncate(def_laps)));

    const def_racers: u32 = gv.SettingGetU("general", "default_racers") orelse 12;
    if (def_racers >= 1 and def_racers <= 12)
        _ = mem.write(0x50C558, u8, @as(u8, @truncate(def_racers))); // racers
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    QuickRaceMenu.close();
}

// HOOKS

export fn InputUpdateB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;
    QuickRaceMenu.input_confirm_state = gv.InputGetKbRaw(QuickRaceMenu.input_confirm);
    QuickRaceMenu.input_x_dec_state = gv.InputGetKbRaw(QuickRaceMenu.input_x_dec);
    QuickRaceMenu.input_x_inc_state = gv.InputGetKbRaw(QuickRaceMenu.input_x_inc);
    QuickRaceMenu.input_y_dec_state = gv.InputGetKbRaw(QuickRaceMenu.input_y_dec);
    QuickRaceMenu.input_y_inc_state = gv.InputGetKbRaw(QuickRaceMenu.input_y_inc);
}

export fn TimerUpdateB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    // FIXME: run sleep when in the pre-race cutscene/camera swing
    if (gs.in_race.on() and mem.read(rc.ADDR_GUI_STOPPED, u32) == 0)
        QuickRaceMenu.FpsTimer.Sleep();
}

// FIXME: settings toggles for both of these
// FIXME: probably want this mid-engine update, immediately before Jdge gets processed?
export fn EarlyEngineUpdateB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    // Quick Reload
    if (gs.in_race.on() and gv.InputGetKbDown(.@"2") and gv.InputGetKbPressed(.ESCAPE)) {
        const jdge = r.DerefEntity(.Jdge, 0, 0);
        rf.TriggerLoad_InRace(jdge, rc.MAGIC_RSTR);
    }

    // Quick Race Menu
    if (gs.in_race.on() and !gs.player.in_race_results.on())
        QuickRaceMenu.update();
}

export fn TextRenderB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    if (!gv.SettingGetB("practice", "practice_tool_enable").?) return;

    if (gs.in_race.on()) {
        if (gs.in_race == .JustOn) race.reset();

        const race_times: [6]f32 = r.ReadRaceDataValue(0x60, [6]f32);
        const total_time: f32 = race_times[5];

        if (gs.player.in_race_count.on()) {
            if (gs.player.in_race_count == .JustOn) {
                // ...
            }
        } else if (gs.player.in_race_results.on()) {
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

            const upg_postfix = if (gs.player.upgrades) "" else "  NU";
            RenderRaceResultHeader(0, "{d:>2.0}/{s}{s}", .{
                gs.fps_avg,
                rc.UpgradeNames[gs.player.upgrades_lv[0]],
                upg_postfix,
            });

            for (0..7) |i| RenderRaceResultStatUpgrade(
                2 + @as(u8, @truncate(i)),
                @as(u8, @truncate(i)),
                gs.player.upgrades_lv[i],
                gs.player.upgrades_hp[i],
            );

            RenderRaceResultStatU(10, "Deaths", race.total_deaths);
            RenderRaceResultStatTime(11, "Boost Time", race.total_boost_duration);
            RenderRaceResultStatF(12, "Boost Ratio", race.total_boost_ratio);
            RenderRaceResultStatTime(13, "First Boost", race.first_boost_time);
            RenderRaceResultStatTime(14, "Underheat Time", race.total_underheat);
            RenderRaceResultStatTime(15, "Fire Finish", race.fire_finish_duration);
            RenderRaceResultStatTime(16, "Overheat Time", race.total_overheat);
        } else {
            if (gs.player.dead == .JustOn) race.total_deaths += 1;

            if (gs.player.boosting == .JustOn) race.set_last_boost_start(total_time);
            if (gs.player.boosting.on()) race.set_total_boost(total_time);
            if (gs.player.boosting == .JustOff) race.set_total_boost(total_time);

            if (gs.player.underheating == .JustOn) race.set_last_underheat_start(total_time);
            if (gs.player.underheating.on()) race.set_total_underheat(total_time);
            if (gs.player.underheating == .JustOff) race.set_total_underheat(total_time);

            if (gs.player.overheating == .JustOn) race.set_last_overheat_start(total_time);
            if (gs.player.overheating.on()) race.set_total_overheat(total_time);
            if (gs.player.overheating == .JustOff) race.set_total_overheat(total_time);
        }
    }
}
