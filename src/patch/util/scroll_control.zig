const Self = @This();

const std = @import("std");

const win32 = @import("../import/import.zig").win32;
const win32kb = win32.ui.input.keyboard_and_mouse;

const mem = @import("memory.zig");
const input = @import("input.zig");
const r = @import("racer.zig");
const rc = r.constants;
const rf = r.functions;

pub const ScrollControl = struct {
    scroll: f32 = 0,
    scroll_buf: f32 = 0,
    scroll_time: f32, // time until max scroll speed
    scroll_units: f32, // units per second at max scroll speed
    input_dec: win32kb.VIRTUAL_KEY,
    input_inc: win32kb.VIRTUAL_KEY,

    pub fn update(self: *ScrollControl, val: *i32, max: i32, wrap: bool) void {
        const dt = mem.read(rc.ADDR_TIME_FRAMETIME, f32);

        var inc: f32 = 0;
        if (input.get_kb_pressed(self.input_dec)) inc -= 1;
        if (input.get_kb_pressed(self.input_inc)) inc += 1;
        if (input.get_kb_released(self.input_dec) or input.get_kb_released(self.input_inc)) {
            self.scroll = 0;
            self.scroll_buf = 0;
        }
        if (input.get_kb_down(self.input_dec)) self.scroll -= dt;
        if (input.get_kb_down(self.input_inc)) self.scroll += dt;

        const scroll: f32 = std.math.clamp(self.scroll / self.scroll_time, -1, 1);
        inc += std.math.pow(f32, scroll, 2) * dt * self.scroll_units * std.math.sign(scroll);
        self.scroll_buf += inc;

        const inc_i: i32 = @intFromFloat(self.scroll_buf);
        self.scroll_buf -= @floatFromInt(inc_i);

        const new_val = val.* + inc_i;
        val.* = if (wrap) @mod(new_val, max) else std.math.clamp(new_val, 0, max - 1);
    }
};
