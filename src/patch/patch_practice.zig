pub const Self = @This();

const std = @import("std");

const settings = @import("settings.zig");
const s = settings.state;
const global = @import("global.zig");
const GlobalState = global.GlobalState;

const menu = @import("util/menu.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = r.constants;
const rf = r.functions;

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

// QUICK RACE MENU

// TODO: generalize menuing and add hooks to let plugins add pages to the menu
// TODO: add standard race settings (mirror, etc.)
// TODO: add convenience buttons for MU/NU
// TODO: also tracking related values for coherency, e.g. adjusting selected circuit
const menu_quickrace = struct {
    var menu_active: bool = false;
    var initialized: bool = false;

    const values = struct {
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
        .max = 10,
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
        global.Freeze.freeze();
        data.idx = 0;
        menu_active = true;
    }

    fn close() void {
        global.Freeze.unfreeze();
        _ = mem.write(rc.ADDR_PAUSE_STATE, u8, 3);
        menu_active = false;
    }

    fn update() void {
        init();

        const pausestate: u8 = mem.read(rc.ADDR_PAUSE_STATE, u8);
        if (menu_active and input.get_kb_pressed(.ESCAPE)) {
            close();
        } else if (pausestate == 2 and input.get_kb_pressed(.ESCAPE)) {
            open();
        }

        if (menu_active) data.update_and_draw();
    }
};

// PRACTICE MODE VISUALIZATION

const mode_vis = struct {
    const scale: f32 = 0.35;
    const x_rt: u16 = 640 - @round(32 * scale);
    const y_bt: u16 = 480 - @round(32 * scale);
    var spr: u32 = undefined;
    var tl: u16 = undefined;
    var tr: u16 = undefined;
    var bl: u16 = undefined;
    var br: u16 = undefined;

    fn init() void {
        spr = rf.swrQuad_LoadTga("annodue/images/corner_round_32.tga", 8000);
        init_single(&tl, false, false);
        init_single(&tr, false, true);
        init_single(&bl, true, false);
        init_single(&br, true, true);
    }

    fn init_single(id: *u16, bt: bool, rt: bool) void {
        id.* = r.InitNewQuad(spr);
        rf.swrQuad_SetFlags(id.*, 1 << 15 | 1 << 16);
        if (rt) rf.swrQuad_SetFlags(id.*, 1 << 2);
        if (!bt) rf.swrQuad_SetFlags(id.*, 1 << 3);
        rf.swrQuad_SetColor(id.*, 0xFF, 0xFF, 0x9C, 0xFF);
        rf.swrQuad_SetPosition(id.*, if (rt) x_rt else 0, if (bt) y_bt else 0);
        rf.swrQuad_SetScale(id.*, scale, scale);
    }

    fn update(active: bool, cr: u8, cg: u8, cb: u8) void {
        rf.swrQuad_SetActive(tl, @intFromBool(active));
        rf.swrQuad_SetActive(tr, @intFromBool(active));
        rf.swrQuad_SetActive(bl, @intFromBool(active));
        rf.swrQuad_SetActive(br, @intFromBool(active));
        if (active) {
            rf.swrQuad_SetColor(tl, cr, cg, cb, 0xFF);
            rf.swrQuad_SetColor(tr, cr, cg, cb, 0xFF);
            rf.swrQuad_SetColor(bl, cr, cg, cb, 0xFF);
            rf.swrQuad_SetColor(br, cr, cg, cb, 0xFF);
        }
    }
};

// END RACE STAT HELPERS

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

// HOOK FUNCTIONS

pub fn EarlyEngineUpdate_Before(gs: *GlobalState, initialized: bool) void {
    _ = initialized;
    if (!s.prac.get("practice_tool_enable", bool) or !s.prac.get("overlay_enable", bool)) return;

    if (gs.in_race.isOn()) {
        const before_endrace: bool = r.ReadPlayerValue(0x60, u32) & (1 << 5) > 0;
        if (before_endrace) menu_quickrace.update();
    }
}

pub fn InitRaceQuads_After(gs: *GlobalState, initialized: bool) void {
    _ = initialized;
    _ = gs;
    mode_vis.init();
}

pub fn TextRender_Before(gs: *GlobalState, initialized: bool) void {
    _ = initialized;
    if (!s.prac.get("practice_tool_enable", bool) or !s.prac.get("overlay_enable", bool)) return;

    if (gs.in_race.isOn()) {
        if (gs.in_race == .JustOn) race.reset();
        var buf: [127:0]u8 = undefined;

        const lap: u8 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x78 }, u8);
        const race_times: [6]f32 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x60 }, [6]f32);
        const lap_times: []const f32 = race_times[0..5];
        const total_time: f32 = race_times[5];

        // FIXME: move flashing logic out of here
        // FIXME: make the flashing start when you activate practice mode
        var f_r: u8 = 0xFF;
        var f_g: u8 = 0xFF;
        var f_b: u8 = 0x9C;
        var f_on: bool = false;
        if (gs.practice_mode) {
            const r_range: u8 = 0xFF / 2;
            const g_range: u8 = 0xFF / 2;
            const b_range: u8 = 0x9C / 2;
            if (total_time <= 0) {
                const timer: f32 = r.ReadEntityValue(.Jdge, 0, 0x0C, f32);
                const flash_cycle: f32 = std.math.clamp((std.math.cos(timer * std.math.pi * 12) * 0.5 + 0.5) * std.math.pow(f32, timer / 3, 3), 0, 3);
                f_r -= @intFromFloat(r_range * flash_cycle);
                f_g -= @intFromFloat(g_range * flash_cycle);
                f_b -= @intFromFloat(b_range * flash_cycle);
            }
            // TODO: move text to eventual toast system
            //rf.swrText_CreateEntry1(640 - 16, 480 - 16, f_rg, f_rg, f_b, 190, "~F0~s~rPractice Mode");
            f_on = true;
        }
        mode_vis.update(f_on, f_r, f_g, f_b);

        if (gs.player.in_race_count.isOn()) {
            if (gs.player.in_race_count == .JustOn) {
                // ...
            }
        } else if (gs.player.in_race_results.isOn()) {
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

            if (gs.practice_mode) {
                // draw heat timer
                const heat_s: f32 = gs.player.heat / gs.player.heat_rate;
                const cool_s: f32 = (100 - gs.player.heat) / gs.player.cool_rate;
                const heat_timer: f32 = if (gs.player.boosting.isOn()) heat_s else cool_s;
                const heat_color: u32 = if (gs.player.boosting.isOn()) 5 else if (gs.player.heat < 100) 2 else 7;
                _ = std.fmt.bufPrintZ(
                    &buf,
                    "~F0~{d}~s~r{d:0>5.3}",
                    .{ heat_color, heat_timer },
                ) catch unreachable;
                rf.swrText_CreateEntry1((320 - 68) * 2, 168 * 2, 255, 255, 255, 190, &buf);

                // draw lap times
                for (lap_times, 0..) |t, i| {
                    if (t < 0) break;
                    // FIXME: move the time formatting logic out of here
                    const t_ms: u32 = @as(u32, @intFromFloat(@round(lap_times[i] * 1000)));
                    const min: u32 = (t_ms / 1000) / 60;
                    const sec: u32 = (t_ms / 1000) % 60;
                    const ms: u32 = t_ms % 1000;
                    const col: u8 = if (lap == i) 255 else 170;
                    _ = std.fmt.bufPrintZ(
                        &buf,
                        "~F1~s{d}  {d}:{d:0>2}.{d:0>3}",
                        .{ i + 1, min, sec, ms },
                    ) catch unreachable;
                    const y: u8 = 128 + @as(u8, @truncate(i)) * 16;
                    rf.swrText_CreateEntry1(48, y, col, col, col, 190, &buf);
                }
            }
        }
    }
}
