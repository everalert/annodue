const std = @import("std");

const RingBuffer = @import("../util/ring_buffer.zig").RingBuffer;
const nxf = @import("../util/normalized_transform.zig");
const fl = @import("../util/flash.zig");

const app = @import("../appinfo.zig");
const GlobalSt = app.GLOBAL_STATE;
const GlobalFn = app.GLOBAL_FUNCTION;

const r = @import("racer");
const rt = r.Text;

// TODO: post-toast callback functions
// TODO: decide whether the spawning/scrolling behaviour should be reversed (like DOOM)

// TOAST SYSTEM

pub const ToastCallback = *const fn () callconv(.C) void;

pub const ToastItem = extern struct {
    timer: f32 = 0,
    color: u32 = 0xFFFFFF00,
    text: [107:0]u8 = undefined,
    //callback: ?ToastCallback, // ??
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
    const max_len: u32 = 32;
    var buffer: RingBuffer(ToastItem, max_len) = .{};
    var item: ToastItem = .{};

    pub fn NewToast(text: [*:0]const u8, color: u32) callconv(.C) bool {
        _ = std.fmt.bufPrintZ(&item.text, "{s}", .{text}) catch return false;
        item.timer = 0;
        item.color = color & 0xFFFFFF00;
        return buffer.enqueue(&item);
    }
};

// HOOK FUNCTIONS

pub fn EarlyEngineUpdateA(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
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

        break :blk @as(i16, @intFromFloat(-nxf.fadeOut2(item.timer / ToastSystem.dur_in) * ToastSystem.row_h));
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
            a = @intFromFloat(nxf.fadeIn2(item.timer / ToastSystem.dur_in) * 255);
        } else if (item.timer >= ToastSystem.t_out) {
            a = @intFromFloat(nxf.fadeOut2((item.timer - ToastSystem.t_out) / ToastSystem.dur_out) * 255);
        }
        const color: u32 = fl.flash_color(item.color, item.timer, ToastSystem.dur_flash) | a;

        rt.DrawText(16, 8 + y_off + ToastSystem.row_h * i, "{s}", .{item.text}, color, null) catch @panic("failed to draw toast text");
    }
}
