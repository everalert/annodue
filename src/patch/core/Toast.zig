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
    const dur_in: f32 = 0.3;
    const dur_flash: f32 = 0.9;
    const dur_out: f32 = 0.1;
    const t_out: f32 = dur - dur_out;
    const row_h: i16 = 9;
    const max_len: u32 = 32;
    var buffer: RingBuffer(ToastItem, max_len) = .{};
    var item: ToastItem = .{};

    pub fn NewToast(text: [*:0]const u8, color: u32) callconv(.C) bool {
        _ = std.fmt.bufPrintZ(&item.text, "{s}", .{text}) catch return false;
        item.timer = 0;
        item.color = color & 0xFFFFFF00;
        n_visible += 1;
        return buffer.push(&item);
    }
};

// HOOK FUNCTIONS

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn Draw2DB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    const num_vis: *u32 = &ToastSystem.n_visible;
    const num_items: *const u32 = &ToastSystem.buffer.items.len;

    var y_off: i16 = 0;
    var r_start: u32 = @intCast(ToastSystem.buffer.b); // range
    for (0..num_vis.*) |i| {
        const item: *ToastItem = &ToastSystem.buffer.items[(r_start + i) % num_items.*];

        item.timer += gs.dt_f;
        if (item.timer >= ToastSystem.dur) {
            _ = ToastSystem.buffer.dequeue(null);
            ToastSystem.n_visible -= 1;
            continue;
        }

        if (item.timer >= ToastSystem.t_out)
            y_off -= @intFromFloat(nxf.pow3((item.timer - ToastSystem.t_out) / ToastSystem.dur_out) * ToastSystem.row_h);
    }

    r_start = @intCast(ToastSystem.buffer.b); // range
    for (0..num_vis.*) |i| {
        const item: *ToastItem = &ToastSystem.buffer.items[(r_start + i) % num_items.*];

        var a: u32 = 255;
        if (item.timer <= ToastSystem.dur_in) {
            a = @intFromFloat(nxf.fadeIn2(item.timer / ToastSystem.dur_in) * 255);
        } else if (item.timer >= ToastSystem.t_out) {
            a = @intFromFloat(nxf.fadeOut2((item.timer - ToastSystem.t_out) / ToastSystem.dur_out) * 255);
        }
        const color: u32 = fl.flash_color(item.color, item.timer, ToastSystem.dur_flash) | a;

        _ = gf.GDrawText(.System, rt.MakeText(4, 2 + y_off + ToastSystem.row_h * @as(i16, @intCast(i)), "{s}", .{item.text}, color, null) catch @panic("failed to draw toast text"));
    }
}
