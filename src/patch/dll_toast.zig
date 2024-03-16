const Self = @This();

const std = @import("std");

const GlobalSt = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = r.functions;
const rc = r.constants;
const rt = r.text;
const rto = rt.TextStyleOpts;

const PLUGIN_NAME: [*:0]const u8 = "Toast Test";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// to cleanup
// - remove 'toast' from build.zig
const dbg = @import("util/debug.zig");

// RING BUFFER

fn RingBuffer(comptime T: type, comptime size: u32) type {
    return extern struct {
        items: [size]T = undefined,
        len: u32 = 0,
        b: i32 = 0,
        f: i32 = 0,

        pub fn push(self: *@This(), in: *const T) bool {
            const next: i32 = @mod(self.f + 1, @as(i32, @intCast(size)));
            if (next == self.b) return false;

            self.items[@intCast(self.f)] = in.*;
            self.f = next;
            self.len = self.used_len();
            return true;
        }

        pub fn pop(self: *@This(), out: ?*T) bool {
            if (self.f == self.b) return false;

            self.f = @mod(self.f - 1, @as(i32, @intCast(size)));
            if (out) |o| o.* = self.items[@intCast(self.f)];
            self.len = self.used_len();
            return true;
        }

        pub fn enqueue(self: *@This(), in: *const T) bool {
            const next: i32 = @mod(self.b - 1, @as(i32, @intCast(size)));
            if (next == self.f) return false;

            self.b = next;
            self.items[@intCast(self.b)] = in.*;
            self.len = self.used_len();
            return true;
        }

        pub fn dequeue(self: *@This(), out: ?*T) bool {
            if (self.f == self.b) return false;

            if (out) |o| o.* = self.items[@intCast(self.b)];
            self.b = @mod(self.b + 1, @as(i32, @intCast(size)));
            self.len = self.used_len();
            return true;
        }

        fn used_len(self: *@This()) u32 {
            return @intCast(@mod(self.f - self.b, size));
        }

        pub fn iterator() void {} // TODO: impl
    };
}

// TOAST STUFF

pub const ToastItem = extern struct {
    timer: f32 = 0,
    color: u32 = 0xFFFFFF00,
    text: [107:0]u8 = undefined,
    //callback: *const fn() void, // ??
};

pub const ToastSystem = extern struct {
    const n_visible_max: u32 = 8;
    var n_visible: u32 = 0;
    const dur: f32 = 3;
    const dur_in: f32 = 0.1;
    const dur_flash: f32 = 1.5;
    const dur_out: f32 = 0.3;
    const t_out: f32 = dur - dur_out;
    const row_h: i16 = 12;
    const max_len: u32 = @intCast(480 / row_h);
    var buffer: RingBuffer(ToastItem, max_len) = .{};
    var item: ToastItem = .{};
    //var animating_new: bool = false;

    pub fn NewToast(text: [*:0]const u8, color: u32) callconv(.C) bool {
        _ = std.fmt.bufPrintZ(&item.text, "{s}", .{text}) catch return false;
        item.timer = 0;
        item.color = color & 0xFFFFFF00;
        return buffer.enqueue(&item);
    }
};

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return PLUGIN_NAME;
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return PLUGIN_VERSION;
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

export fn OnInitLate(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

// HOOKS

fn flip(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return 1 - n;
}

fn pow2(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return n * n;
}

fn pow3(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return n * n * n;
}

fn fadeOut(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return flip(pow2(n));
}

fn fadeIn(n: f32) f32 {
    std.debug.assert(n >= 0 and n <= 1);
    return flip(pow2(flip(n)));
}

fn flash(color: u32, time: f32, dur: f32) u32 {
    if (time >= dur) return color;

    var c = color;
    var col: [4]u8 align(4) = @as(*[4]u8, @ptrCast(&c)).*;

    const tscale: f32 = pow2(flip(time / dur));
    const cycle: f32 = @cos(time * std.math.pi * 12) * 0.5 + 0.5;
    for (0..4) |i| col[i] -= @intFromFloat(@as(f32, @floatFromInt(col[i] / 2)) * cycle * tscale);

    //dbg.ConsoleOut("{any}\n", .{cycle}) catch {};
    return @as(*u32, @ptrCast(&col)).*;
}

const msg = @import("util/message.zig");
var buf: [107:0]u8 = undefined;
var x256 = std.rand.DefaultPrng.init(0);
var rng = x256.random();

export fn EarlyEngineUpdateA(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = std.fmt.bufPrintZ(&buf, "{d}", .{gs.timestamp}) catch {};
    const c: u32 = rc.TEXT_COLOR_PRESET[rng.uintAtMost(u32, 9)] << 8;
    if (gf.InputGetKb(.Y, .JustOn)) _ = ToastSystem.NewToast(&buf, c);

    const r_start: u32 = @intCast(ToastSystem.buffer.b);
    const r_end: u32 = r_start + ToastSystem.buffer.len;
    const len: u32 = ToastSystem.buffer.len;
    const n_vis: *u32 = &ToastSystem.n_visible;
    const i_len: *const u32 = &ToastSystem.buffer.items.len;

    const y_off: i16 = blk: {
        if (r_end == r_start) break :blk 0;

        if (n_vis.* == 0) n_vis.* += 1;
        var item: *ToastItem = &ToastSystem.buffer.items[(r_end - n_vis.*) % i_len.*];

        if (item.timer > ToastSystem.dur_in) {
            if (n_vis.* < len and n_vis.* < ToastSystem.n_visible_max) {
                n_vis.* += 1;
                item = &ToastSystem.buffer.items[(r_end - n_vis.*) % i_len.*];
            } else break :blk 0;
        }

        break :blk @as(i16, @intFromFloat(-fadeOut(item.timer / ToastSystem.dur_in) * ToastSystem.row_h));
    };

    const vis: u32 = n_vis.*;
    for (0..vis) |r_cur| {
        const i: i16 = @intCast(vis - r_cur - 1);
        const item: *ToastItem = &ToastSystem.buffer.items[(r_end - r_cur - 1) % i_len.*];

        item.timer += gs.dt_f;
        if (item.timer >= ToastSystem.dur) {
            _ = ToastSystem.buffer.pop(null);
            ToastSystem.n_visible -= 1;
            continue;
        }

        var a: u32 = 255;
        if (item.timer <= ToastSystem.dur_in) {
            a = @intFromFloat(fadeIn(item.timer / ToastSystem.dur_in) * 255);
        } else if (item.timer >= ToastSystem.t_out) {
            a = @intFromFloat(fadeOut((item.timer - ToastSystem.t_out) / ToastSystem.dur_out) * 255);
        }

        rt.DrawText(16, 8 + y_off + ToastSystem.row_h * i, "{s}", .{
            item.text,
        }, flash(item.color, item.timer, ToastSystem.dur_flash) | a, null) catch |e| msg.ErrMessage("toast", e);
    }
    //rt.DrawText(0, 0, "{d:0>2}/{d:0>2} {d:0>2}", .{
    //    ToastSystem.buffer.len, ToastSystem.buffer.items.len, ToastSystem.n_visible,
    //}, null, null) catch |e| msg.ErrMessage("toast", e);
}
