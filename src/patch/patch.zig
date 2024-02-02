const std = @import("std");
const user32 = std.os.windows.user32;

const VirtualAlloc = std.os.windows.VirtualAlloc;
const VirtualFree = std.os.windows.VirtualFree;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const MEM_RELEASE = std.os.windows.MEM_RELEASE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;

const MessageBoxA = user32.MessageBoxA;
const MB_OK = user32.MB_OK;
const MB_ICONINFORMATION = user32.MB_ICONINFORMATION;

const ver_major: u32 = 0;
const ver_minor: u32 = 0;
const ver_patch: u32 = 1;

const mp = @import("patch_multiplayer.zig");
const gen = @import("patch_general.zig");
const mem = @import("util/memory.zig");
const UpgradeNames = @import("util/racer_const.zig").UpgradeNames;
const UpgradeCategories = @import("util/racer_const.zig").UpgradeCategories;
const swrText_CreateEntry1 = @import("util/racer_fn.zig").swrText_CreateEntry1;
const SettingsGroup = @import("util/settings.zig").SettingsGroup;
const SettingsManager = @import("util/settings.zig").SettingsManager;
const ini = @import("import/ini/ini.zig");

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

const s = struct { // FIXME: yucky
    var manager: SettingsManager = undefined;
    var gen: SettingsGroup = undefined;
    var prac: SettingsGroup = undefined;
    var mp: SettingsGroup = undefined;
};

fn PtrMessage(alloc: std.mem.Allocator, ptr: usize, label: []const u8) void {
    var buf = std.fmt.allocPrintZ(alloc, "{s}: 0x{x}", .{ label, ptr }) catch unreachable;
    _ = MessageBoxA(null, buf, "annodue.dll", MB_OK);
}

fn ErrMessage(label: []const u8, err: []const u8) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var bufe = std.fmt.allocPrintZ(alloc, "[ERROR] {s}: {s}", .{ label, err }) catch unreachable;
    _ = MessageBoxA(null, bufe, "annodue.dll", MB_OK);
}

fn GameLoopAfter() void {
    const state = struct {
        var initialized: bool = false;
    };

    if (!state.initialized) {
        const def_laps: u32 = s.gen.get("default_laps", u32);
        if (def_laps >= 1 and def_laps <= 5) {
            const laps: usize = mem.deref(&.{ 0x4BFDB8, 0x8F });
            _ = mem.write(laps, u8, @as(u8, @truncate(def_laps)));
        }
        const def_racers: u32 = s.gen.get("default_racers", u32);
        if (def_racers >= 1 and def_racers <= 12) {
            const addr_racers: usize = 0x50C558;
            _ = mem.write(addr_racers, u8, @as(u8, @truncate(def_racers)));
        }

        state.initialized = true;
    }

    if (s.gen.get("rainbow_timer_enable", bool)) {
        gen.PatchHudTimerColRotate();
    }
}

fn HookGameLoop(memory: usize) usize {
    const off_call: usize = 0x49CE2A;
    const off_gameloop: usize = mem.addr_from_call(off_call);

    var offset: usize = memory;

    _ = mem.call(off_call, offset);

    offset = mem.call(offset, off_gameloop);
    offset = mem.call(offset, @intFromPtr(&GameLoopAfter));
    offset = mem.retn(offset);
    offset = mem.nop_align(offset, 16);

    return offset;
}

fn GameEnd() void {
    defer s.manager.deinit();
    defer s.gen.deinit();
    defer s.mp.deinit();
}

fn HookGameEnd(memory: usize) usize {
    const exit1_off: usize = 0x49CE31;
    const exit2_off: usize = 0x49CE3D;
    const exit1_len: usize = exit2_off - exit1_off - 1; // excluding retn
    const exit2_len: usize = 0x49CE48 - exit2_off - 1; // excluding retn
    var offset: usize = memory;

    offset = mem.detour(offset, exit1_off, exit1_len, &GameEnd);
    offset = mem.detour(offset, exit2_off, exit2_len, &GameEnd);

    return offset;
}

const race_stat_x: u16 = 192;
const race_stat_y: u16 = 48;
const race_stat_col: u8 = 255;

fn RenderRaceResultStat1(i: u8, label: [*:0]const u8) void {
    var buf: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "~F0~s~c{s}", .{label}) catch unreachable;
    swrText_CreateEntry1(640 - race_stat_x, race_stat_y + i * 12, race_stat_col, race_stat_col, race_stat_col, 255, &buf);
}

fn RenderRaceResultStat2(i: u8, label: [*:0]const u8, value: [*:0]const u8) void {
    var bufl: [127:0]u8 = undefined;
    var bufv: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&bufl, "~F0~s~r{s}", .{label}) catch unreachable;
    _ = std.fmt.bufPrintZ(&bufv, "~F0~s{s}", .{value}) catch unreachable;
    swrText_CreateEntry1(640 - race_stat_x - 8, race_stat_y + i * 12, race_stat_col, race_stat_col, race_stat_col, 255, &bufl);
    swrText_CreateEntry1(640 - race_stat_x + 8, race_stat_y + i * 12, race_stat_col, race_stat_col, race_stat_col, 255, &bufv);
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
    _ = std.fmt.bufPrintZ(&buf, "{s}{d:0>3} ~1{s}", .{ hp_col, hp, UpgradeNames[cat * 6 + lv] }) catch unreachable;
    RenderRaceResultStat2(i, UpgradeCategories[cat], &buf);
}

fn TextRenderBefore() void {
    //const off_scene_id: usize = 0xE9BA62; // u16
    const off_in_race: usize = 0xE9BB81; //u8
    //const off_in_tournament: usize = 0x50C450; // u8
    //const off_pause_state: usize = 0x50C5F0; // u8

    if (s.prac.get("practice_tool_enable", bool) and s.prac.get("overlay_enable", bool)) {
        const state = struct {
            var fps: f32 = 0;
            var upgrades: bool = false;
            var upgrades_lv: [7]u8 = undefined;
            var upgrades_hp: [7]u8 = undefined;
            var was_in_race: bool = false;
            var was_in_race_count: bool = false;
            var was_in_race_results: bool = false;
            var was_boosting: bool = false;
            var was_underheating: bool = true;
            var was_overheating: bool = false;
            var was_dead: bool = false;
            var total_deaths: u32 = 0;
            var total_boost_duration: f32 = 0;
            var total_boost_ratio: f32 = 0;
            var total_underheat: f32 = 0;
            var total_overheat: f32 = 0;
            var fire_finish_duration: f32 = 0;
            var last_boost_started: f32 = 0;
            var last_boost_started_total: f32 = 0;
            var last_underheat_started: f32 = 0;
            var last_underheat_started_total: f32 = 0;
            var last_overheat_started: f32 = 0;
            var last_overheat_started_total: f32 = 0;
            var heat_rate: f32 = 0;
            var cool_rate: f32 = 0;

            fn reset_race() void {
                was_in_race_count = false;
                was_in_race_results = false;
                was_boosting = false;
                was_underheating = true; // you start the race underheating
                was_overheating = false;
                was_dead = false;
                total_deaths = 0;
                total_boost_duration = 0;
                total_boost_ratio = 0;
                total_underheat = 0;
                total_overheat = 0;
                fire_finish_duration = 0;
                last_boost_started = 0;
                last_boost_started_total = 0;
                last_underheat_started = 0;
                last_underheat_started_total = 0;
                last_overheat_started = 0;
                last_overheat_started_total = 0;
                heat_rate = mem.deref_read(&.{ 0x4D78A4, 0x84, 0x8C }, f32);
                cool_rate = mem.deref_read(&.{ 0x4D78A4, 0x84, 0x90 }, f32);
                const u: [14]u8 = mem.deref_read(&.{ 0x4D78A4, 0x0C, 0x41 }, [14]u8);
                upgrades_lv = u[0..7].*;
                upgrades_hp = u[7..14].*;
                var i: u8 = 0;
                upgrades = while (i < 7) : (i += 1) {
                    if (u[i] > 0 and u[7 + i] > 0) break true;
                } else false;
            }

            fn set_last_boost_start(time: f32) void {
                last_boost_started_total = total_boost_duration;
                last_boost_started = time;
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

        const in_race: bool = mem.read(off_in_race, u8) > 0;
        const in_race_new: bool = state.was_in_race != in_race;
        state.was_in_race = in_race;

        const dt_f: f32 = mem.deref_read(&.{0xE22A50}, f32);
        const fps_res: f32 = 10;
        state.fps = (state.fps * (fps_res - 1) + (1 / dt_f)) / fps_res;

        if (in_race) {
            if (in_race_new) state.reset_race();

            const flags1: u32 = mem.deref_read(&.{ 0x4D78A4, 0x84, 0x60 }, u32);
            const in_race_count: bool = (flags1 & (1 << 0)) > 0;
            const in_race_count_new: bool = state.was_in_race_count != in_race_count;
            state.was_in_race_count = in_race_count;
            const in_race_results: bool = (flags1 & (1 << 5)) == 0;
            const in_race_results_new: bool = state.was_in_race_results != in_race_results;
            state.was_in_race_results = in_race_results;

            const lap: u8 = mem.deref_read(&.{ 0x4D78A4, 0x78 }, u8);
            const race_times: [6]f32 = mem.deref_read(&.{ 0x4D78A4, 0x60 }, [6]f32);
            const lap_times: []const f32 = race_times[0..5];
            const total_time: f32 = race_times[5];

            if (in_race_count) {
                if (in_race_count_new) {
                    // ...
                }
            } else if (in_race_results) {
                if (in_race_results_new) {
                    if (state.was_boosting) state.set_total_boost(total_time);
                    if (state.was_underheating) state.set_total_underheat(total_time);
                    if (state.was_overheating) {
                        state.set_fire_finish_duration(total_time);
                        state.set_total_overheat(total_time);
                    }
                }

                var buf_tfps: [63:0]u8 = undefined;
                _ = std.fmt.bufPrintZ(&buf_tfps, "{d:>2.0}/{s}", .{ state.fps, UpgradeNames[state.upgrades_lv[0]] }) catch unreachable;
                RenderRaceResultStat1(0, &buf_tfps);

                var buf_upg: [63:0]u8 = undefined;
                _ = std.fmt.bufPrintZ(&buf_upg, "{s}Upgrades", .{if (state.upgrades) "" else "NO "}) catch unreachable;
                RenderRaceResultStat1(2, &buf_upg);

                var i: u8 = 0;
                while (i < 7) : (i += 1) {
                    RenderRaceResultStatUpgrade(4 + i, i, state.upgrades_lv[i], state.upgrades_hp[i]);
                }

                RenderRaceResultStatU(12, "Deaths", state.total_deaths);
                RenderRaceResultStatTime(13, "Fire Finish", state.fire_finish_duration);
                RenderRaceResultStatTime(14, "Boost Time", state.total_boost_duration);
                RenderRaceResultStatF(15, "Boost Ratio", state.total_boost_ratio);
                RenderRaceResultStatTime(16, "Underheat Time", state.total_underheat);
                RenderRaceResultStatTime(17, "Overheat Time", state.total_overheat);
            } else {
                var i: u8 = 0;
                while (i < lap_times.len and lap_times[i] >= 0) : (i += 1) {
                    const t_ms: u32 = @as(u32, @intFromFloat(@round(lap_times[i] * 1000)));
                    const min: u32 = (t_ms / 1000) / 60;
                    const sec: u32 = (t_ms / 1000) % 60;
                    const ms: u32 = t_ms % 1000;
                    const col: u8 = if (lap == i) 255 else 170;
                    var buf: [63:0]u8 = undefined;
                    _ = std.fmt.bufPrintZ(&buf, "~F1~s{d}  {d}:{d:0>2}.{d:0>3}", .{ i + 1, min, sec, ms }) catch unreachable;
                    swrText_CreateEntry1(48, 128 + i * 16, col, col, col, 255, &buf);
                }

                const dead: bool = (flags1 & (1 << 14)) > 0;
                const dead_new: bool = state.was_dead != dead;
                state.was_dead = dead;
                if (dead and dead_new) state.total_deaths += 1;

                const heat: f32 = mem.deref_read(&.{ 0x4D78A4, 0x84, 0x218 }, f32);
                const engine: [6]u32 = mem.deref_read(&.{ 0x4D78A4, 0x84, 0x2A0 }, [6]u32);

                const boosting: bool = (flags1 & (1 << 23)) > 0;
                const boosting_new: bool = state.was_boosting != boosting;
                state.was_boosting = boosting;
                if (boosting and boosting_new) state.set_last_boost_start(total_time);
                if (boosting) state.set_total_boost(total_time);
                if (!boosting and boosting_new) state.set_total_boost(total_time);

                const underheating: bool = heat >= 100;
                const underheating_new: bool = state.was_underheating != underheating;
                state.was_underheating = underheating;
                if (underheating and underheating_new) state.set_last_underheat_start(total_time);
                if (underheating) state.set_total_underheat(total_time);
                if (!underheating and underheating_new) state.set_total_underheat(total_time);

                var j: u8 = 0;
                const overheating: bool = while (j < 6) : (j += 1) {
                    if (engine[j] & (1 << 3) > 0) break true;
                } else false;
                const overheating_new: bool = state.was_overheating != overheating;
                state.was_overheating = overheating;
                if (overheating and overheating_new) state.set_last_overheat_start(total_time);
                if (overheating) state.set_total_overheat(total_time);
                if (!overheating and overheating_new) state.set_total_overheat(total_time);

                const heat_s: f32 = heat / state.heat_rate;
                const cool_s: f32 = (100 - heat) / state.cool_rate;
                const heat_timer: f32 = if (boosting) heat_s else cool_s;
                const heat_color: []const u8 = if (boosting) "~5" else if (heat < 100) "~2" else "~7";
                var buf: [63:0]u8 = undefined;
                _ = std.fmt.bufPrintZ(&buf, "~F0{s}~s~r{d:0>5.3}", .{ heat_color, heat_timer }) catch unreachable;
                swrText_CreateEntry1((320 - 68) * 2, 168 * 2, 255, 255, 255, 255, &buf);
            }
        }
    }
}

fn HookTextRender(memory: usize) usize {
    const off_call: usize = 0x483F8B; // the first queue processing call
    const off_orig_fn = mem.addr_from_call(off_call);

    var offset: usize = memory;

    _ = mem.call(off_call, offset);

    offset = mem.call(offset, off_orig_fn);
    offset = mem.call(offset, @intFromPtr(&TextRenderBefore));
    offset = mem.retn(offset);
    offset = mem.nop_align(offset, 16);

    return offset;
}

export fn Patch() void {
    const mem_alloc = MEM_COMMIT | MEM_RESERVE;
    const mem_protect = PAGE_EXECUTE_READWRITE;
    const memory = VirtualAlloc(null, patch_size, mem_alloc, mem_protect) catch unreachable;
    var off: usize = @intFromPtr(memory);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // settings

    // FIXME: deinits happen in GameEnd, see HookGameEnd.
    // probably not necessary to deinit at all tho.
    // one other strategy might be to set globals for stuff
    // we need to keep, and go back to deinit-ing. then we also
    // wouldn't have to do hash lookups constantly too.

    s.manager = SettingsManager.init(alloc);
    //defer s.deinit();

    s.gen = SettingsGroup.init(alloc, "general");
    //defer s.gen.deinit();
    s.gen.add("death_speed_mod_enable", bool, false);
    s.gen.add("death_speed_min", f32, 325);
    s.gen.add("death_speed_drop", f32, 140);
    s.gen.add("rainbow_timer_enable", bool, false);
    s.gen.add("ms_timer_enable", bool, false);
    s.gen.add("default_laps", u32, 3);
    s.gen.add("default_racers", u32, 12);
    s.manager.add(&s.gen);

    s.prac = SettingsGroup.init(alloc, "practice");
    //defer s.prac.deinit();
    s.prac.add("practice_tool_enable", bool, false);
    s.prac.add("overlay_enable", bool, false);
    s.manager.add(&s.prac);

    s.mp = SettingsGroup.init(alloc, "multiplayer");
    //defer s.mp.deinit();
    s.mp.add("multiplayer_mod_enable", bool, false); // working?
    s.mp.add("patch_netplay", bool, false); // working? ups ok, coll ?
    s.mp.add("netplay_guid", bool, false); // working?
    s.mp.add("netplay_r100", bool, false); // working
    s.mp.add("patch_audio", bool, false);
    s.mp.add("patch_fonts", bool, false); // working
    s.mp.add("fonts_dump", bool, false); // working?
    s.mp.add("patch_tga_loader", bool, false);
    s.mp.add("patch_trigger_display", bool, false); // working
    s.manager.add(&s.mp);

    s.manager.read_ini(alloc, "annodue/settings.ini") catch unreachable;

    // random stuff

    off = HookGameLoop(off);
    off = HookGameEnd(off);
    off = HookTextRender(off);

    if (s.gen.get("death_speed_mod_enable", bool)) {
        const dsm = s.gen.get("death_speed_min", f32);
        const dsd = s.gen.get("death_speed_drop", f32);
        gen.PatchDeathSpeed(dsm, dsd);
    }
    if (s.gen.get("ms_timer_enable", bool)) {
        gen.PatchHudTimerMs();
    }

    // swe1r-patcher (multiplayer mod) stuff

    if (s.mp.get("multiplayer_mod_enable", bool)) {
        if (s.mp.get("fonts_dump", bool)) {
            // This is a debug feature to dump the original font textures
            _ = mp.DumpTextureTable(alloc, 0x4BF91C, 3, 0, 64, 128, "font0");
            _ = mp.DumpTextureTable(alloc, 0x4BF7E4, 3, 0, 64, 128, "font1");
            _ = mp.DumpTextureTable(alloc, 0x4BF84C, 3, 0, 64, 128, "font2");
            _ = mp.DumpTextureTable(alloc, 0x4BF8B4, 3, 0, 64, 128, "font3");
            _ = mp.DumpTextureTable(alloc, 0x4BF984, 3, 0, 64, 128, "font4");
        }
        if (s.mp.get("patch_fonts", bool)) {
            off = mp.PatchTextureTable(alloc, off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
            off = mp.PatchTextureTable(alloc, off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
            off = mp.PatchTextureTable(alloc, off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
            off = mp.PatchTextureTable(alloc, off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
            off = mp.PatchTextureTable(alloc, off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
        }
        if (s.mp.get("patch_netplay", bool)) {
            const r100 = s.mp.get("netplay_r100", bool);
            const guid = s.mp.get("netplay_guid", bool);
            const traction: u8 = if (r100) 3 else 5;
            var upgrade_lv: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
            var upgrade_hp: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
            const upgrade_lv_ptr: *[7]u8 = @ptrCast(&upgrade_lv);
            const upgrade_hp_ptr: *[7]u8 = @ptrCast(&upgrade_hp);
            off = mp.PatchNetworkUpgrades(off, upgrade_lv_ptr, upgrade_hp_ptr, guid);
            off = mp.PatchNetworkCollisions(off, guid);
        }
        if (s.mp.get("patch_audio", bool)) {
            const sample_rate: u32 = 22050 * 2;
            const bits_per_sample: u8 = 16;
            const stereo: bool = true;
            mp.PatchAudioStreamQuality(sample_rate, bits_per_sample, stereo);
        }
        if (s.mp.get("patch_tga_loader", bool)) {
            off = mp.PatchSpriteLoaderToLoadTga(off);
        }
        if (s.mp.get("patch_trigger_display", bool)) {
            off = mp.PatchTriggerDisplay(off);
        }
    }

    // debug

    if (false) {
        var mb_title = std.fmt.allocPrintZ(alloc, "Annodue {d}.{d}.{d}", .{
            ver_major,
            ver_minor,
            ver_patch,
        }) catch unreachable;
        var mb_launch = "Patching SWE1R...";
        _ = MessageBoxA(null, mb_launch, mb_title, MB_OK);
    }
}
