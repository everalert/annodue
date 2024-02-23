const Self = @This();

const std = @import("std");

const settings = @import("settings.zig");
const s = settings.state;
const global = @import("global.zig");
const GlobalState = global.GlobalState;
const GlobalVTable = global.GlobalVTable;

const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");

const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

// dumping ground for random features i guess

fn PatchDeathSpeed(min: f32, drop: f32) void {
    _ = mem.write(0x4C7BB8, f32, min);
    _ = mem.write(0x4C7BBC, f32, drop);
}

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

fn PatchHudTimerColRotate() void { // 0xFFFFFFBE
    const col = struct {
        const min: u8 = 95;
        const max: u8 = 255;
        var rgb: [3]u8 = .{ 255, 95, 95 };
        var i: u8 = 0;
        var n: u8 = 1;
        fn update() void {
            n = (i + 1) % 3;
            if (rgb[i] == min and rgb[n] == max) i = n;
            n = (i + 1) % 3;
            if (rgb[i] == max and rgb[n] < max) {
                rgb[n] += 1;
            } else {
                rgb[i] -= 1;
            }
        }
    };
    col.update();
    _ = mem.write(0x460E5E, u8, col.rgb[0]); // B, 255
    _ = mem.write(0x460E60, u8, col.rgb[1]); // G, 255
    _ = mem.write(0x460E62, u8, col.rgb[2]); // R, 255
}

fn PatchHudTimerCol(rgba: u32) void { // 0xFFFFFFBE
    _ = mem.write(0x460E5C, u8, @as(u8, @truncate(rgba))); // A, 190
    _ = mem.write(0x460E5E, u8, @as(u8, @truncate(rgba >> 8))); // B, 255
    _ = mem.write(0x460E60, u8, @as(u8, @truncate(rgba >> 16))); // G, 255
    _ = mem.write(0x460E62, u8, @as(u8, @truncate(rgba >> 24))); // R, 255
}

fn PatchHudTimerLabelCol(rgba: u32) void { // 0xFFFFFFBE
    _ = mem.write(0x460E8C, u8, @as(u8, @truncate(rgba))); // A, 190
    _ = mem.write(0x460E8E, u8, @as(u8, @truncate(rgba >> 8))); // B, 255
    _ = mem.write(0x460E90, u8, @as(u8, @truncate(rgba >> 16))); // G, 255
    _ = mem.write(0x460E92, u8, @as(u8, @truncate(rgba >> 24))); // R, 255
}

pub fn init(alloc: std.mem.Allocator, memory: usize) usize {
    _ = alloc;
    if (s.gen.get("death_speed_mod_enable", bool)) {
        const dsm = s.gen.get("death_speed_min", f32);
        const dsd = s.gen.get("death_speed_drop", f32);
        PatchDeathSpeed(dsm, dsd);
    }
    if (s.gen.get("ms_timer_enable", bool)) {
        PatchHudTimerMs();
    }

    return memory;
}

pub fn init_late(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
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
}

// FIXME: probably want this mid-engine update, immediately before Jdge gets processed?
pub fn EarlyEngineUpdate_Before(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    if (gs.in_race.isOn() and input.get_kb_down(.@"2") and input.get_kb_pressed(.ESCAPE)) {
        const jdge: usize = mem.deref_read(&.{ rc.ADDR_ENTITY_MANAGER_JUMPTABLE, @intFromEnum(rc.ENTITY.Jdge) * 4, 0x10 }, usize);
        rf.TriggerLoad_InRace(jdge, rc.MAGIC_RSTR);
    }
}

pub fn TextRender_Before(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    if (s.gen.get("rainbow_timer_enable", bool)) {
        PatchHudTimerColRotate();
    }
}
