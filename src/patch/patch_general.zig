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

    return memory;
}

pub fn TextRender_Before(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    if (s.gen.get("rainbow_timer_enable", bool)) {
        PatchHudTimerColRotate();
    }
}
