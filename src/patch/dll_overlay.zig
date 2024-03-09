const Self = @This();

const std = @import("std");

const GlobalState = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFn;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = r.functions;
const rc = r.constants;
const rt = r.text;
const rto = rt.TextStyleOpts;

const mem = @import("util/memory.zig");
const timing = @import("util/timing.zig");

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

const style_heat = rt.MakeTextHeadStyle(.Small, false, .Gray, .Right, .{rto.ToggleShadow}) catch "";
const style_heat_up = rt.MakeTextHeadStyle(.Small, false, .Red, .Right, .{rto.ToggleShadow}) catch "";
const style_heat_dn = rt.MakeTextHeadStyle(.Small, false, .Blue, .Right, .{rto.ToggleShadow}) catch "";
const style_laptime = rt.MakeTextHeadStyle(.Unk2, true, null, null, .{rto.ToggleShadow}) catch "";

export fn TextRenderB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = initialized;
    if (!gv.SettingGetB("practice", "practice_tool_enable").? or
        !gv.SettingGetB("practice", "overlay_enable").?) return;

    if (gs.in_race.on()) {
        const lap: u8 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x78 }, u8);
        const race_times: [6]f32 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x60 }, [6]f32);
        const lap_times: []const f32 = race_times[0..5];

        if (gs.player.in_race_racing.on() and gs.practice_mode) {
            // draw heat timer
            const heat_s: f32 = gs.player.heat / gs.player.heat_rate;
            const cool_s: f32 = (100 - gs.player.heat) / gs.player.cool_rate;
            const heat_timer: f32 = if (gs.player.boosting.on()) heat_s else cool_s;
            const heat_style = if (gs.player.boosting.on()) style_heat_up else if (gs.player.heat < 100) style_heat_dn else style_heat;
            rt.DrawText(256, 170, "{d:0>5.3}", .{heat_timer}, null, heat_style) catch {};

            // draw lap times
            for (lap_times, 0..) |t, i| {
                if (t < 0) break;
                const x1: u8 = 48;
                const x2: u8 = 64;
                const y: u8 = 128 + @as(u8, @truncate(i)) * 16;
                const col: u32 = if (lap == i) 0xFFFFFFBE else 0xAAAAAABE;
                rt.DrawText(x1, y + 6, "{d}", .{i + 1}, col, null) catch {};
                const lt = timing.RaceTimeFromFloat(lap_times[i]);
                rt.DrawText(x2, y, "{d}:{d:0>2}.{d:0>3}", .{ lt.min, lt.sec, lt.ms }, col, style_laptime) catch {};
            }
        }
    }
}
