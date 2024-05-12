const Self = @This();

const std = @import("std");

const win32 = @import("zigwin32");
const win32kb = win32.ui.input.keyboard_and_mouse;

const st = @import("active_state.zig");
const mem = @import("memory.zig");
const input = @import("../core/input.zig");

const r = @import("racer");
const rt = r.Time;

pub const InputGetFnType = *const fn (st.ActiveState) callconv(.C) bool;

pub const ScrollControl = extern struct {
    scroll: f32 = 0,
    scroll_buf: f32 = 0,
    scroll_time: f32, // time until max scroll speed
    scroll_units: f32, // units per second at max scroll speed
    input_dec: InputGetFnType,
    input_inc: InputGetFnType,

    pub fn UpdateEx(self: *ScrollControl, val: i32, max: i32, wrap: bool) i32 {
        const dt = rt.FRAMETIME.*;

        var inc: f32 = 0;
        if (self.input_dec(.On)) self.scroll -= dt;
        if (self.input_inc(.On)) self.scroll += dt;
        if (self.input_dec(.JustOn)) inc -= 1;
        if (self.input_inc(.JustOn)) inc += 1;
        if (self.input_inc(.JustOff) or self.input_dec(.JustOff)) {
            self.scroll = 0;
            self.scroll_buf = 0;
        }

        const scroll: f32 = std.math.clamp(self.scroll / self.scroll_time, -1, 1);
        inc += std.math.pow(f32, scroll, 2) * dt * self.scroll_units * std.math.sign(scroll);
        self.scroll_buf += inc;

        const inc_i: i32 = @intFromFloat(self.scroll_buf);
        self.scroll_buf -= @floatFromInt(inc_i);

        const new_val = val + inc_i;
        return if (wrap) @mod(new_val, max) else std.math.clamp(new_val, 0, max - 1);
    }
};
