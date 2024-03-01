const Self = @This();

const std = @import("std");

const GlobalState = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFn;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");
const rc = @import("util/racer_const.zig");

const mem = @import("util/memory.zig");

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return "Overlay";
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return "0.0.1";
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

// HOOKS

export fn TextRenderB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    if (!gv.SettingGetB("practice", "practice_tool_enable").? or
        !gv.SettingGetB("practice", "overlay_enable").?) return;

    if (gs.in_race.isOn()) {
        var buf: [127:0]u8 = undefined;

        const lap: u8 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x78 }, u8);
        const race_times: [6]f32 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x60 }, [6]f32);
        const lap_times: []const f32 = race_times[0..5];

        if (gs.player.in_race_racing.isOn() and gs.practice_mode) {
            // draw heat timer
            const heat_s: f32 = gs.player.heat / gs.player.heat_rate;
            const cool_s: f32 = (100 - gs.player.heat) / gs.player.cool_rate;
            const heat_timer: f32 = if (gs.player.boosting.isOn()) heat_s else cool_s;
            const heat_color: u32 = if (gs.player.boosting.isOn()) 5 else if (gs.player.heat < 100) 2 else 7;
            _ = std.fmt.bufPrintZ(&buf, "~f4~{d}~s~r{d:0>5.3}", .{ heat_color, heat_timer }) catch unreachable;
            rf.swrText_CreateEntry1(256, 170, 255, 255, 255, 190, &buf);

            // draw lap times
            for (lap_times, 0..) |t, i| {
                if (t < 0) break;
                const x1: u8 = 48;
                const x2: u8 = 64;
                const y: u8 = 128 + @as(u8, @truncate(i)) * 16;
                const col: u8 = if (lap == i) 255 else 170;
                _ = std.fmt.bufPrintZ(&buf, "~F0~s{d}", .{i + 1}) catch unreachable;
                rf.swrText_CreateEntry1(x1, y + 6, col, col, col, 190, &buf);
                // FIXME: move the time formatting logic out of here
                const t_ms: u32 = @as(u32, @intFromFloat(@round(lap_times[i] * 1000)));
                const min: u32 = (t_ms / 1000) / 60;
                const sec: u32 = (t_ms / 1000) % 60;
                const ms: u32 = t_ms % 1000;
                _ = std.fmt.bufPrintZ(&buf, "~F1~s{d}:{d:0>2}.{d:0>3}", .{ min, sec, ms }) catch unreachable;
                rf.swrText_CreateEntry1(x2, y, col, col, col, 190, &buf);
            }
        }
    }
}
