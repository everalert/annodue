const Self = @This();

const std = @import("std");

const win32 = @import("../import/import.zig").win32;
const win32kb = win32.ui.input.keyboard_and_mouse;

const ScrollControl = @import("scroll_control.zig").ScrollControl;
const input = @import("input.zig");
const r = @import("racer.zig");
const rc = r.constants;
const rf = r.functions;

const InputGetFnType = *const @TypeOf(input.get_kb_pressed);

pub const MenuItem = struct {
    idx: *i32,
    wrap: bool = true,
    label: [*:0]const u8,
    options: []const [*:0]const u8,
    max: i32,
};

// TODO: play menu sounds, e.g. when scrolling
// TODO: maybe a key for quick confirm, so you don't have to scroll
pub const Menu = struct {
    idx: i32 = 0,
    wrap: bool = true,
    title: [*:0]const u8,
    items: []const MenuItem,
    max: i32,
    cancel_fn: ?*fn () void = null,
    cancel_text: ?[*:0]const u8 = null, // default: Cancel
    cancel_key: ?win32kb.VIRTUAL_KEY = null,
    confirm_fn: ?*fn () void = null,
    confirm_text: ?[*:0]const u8 = null, // default: Confirm
    confirm_key: ?win32kb.VIRTUAL_KEY = null,
    x: u16 = 16,
    x_step: u16 = 80,
    x_scroll: ScrollControl,
    y: u16 = 16,
    y_step: u16 = 8,
    y_margin: u16 = 6,
    y_scroll: ScrollControl,
    hl_col: u8 = 3, // ingame predefined colors with ~{n}, default yellow

    pub inline fn UpdateAndDraw(self: *Menu) void {
        self.UpdateAndDrawEx(&input.get_kb_pressed, &input.get_kb_released, &input.get_kb_down);
    }

    pub fn UpdateAndDrawEx(
        self: *Menu,
        get_kb_pressed: InputGetFnType,
        get_kb_released: InputGetFnType,
        get_kb_down: InputGetFnType,
    ) void {
        self.y_scroll.UpdateEx(
            &self.idx,
            self.max,
            self.wrap,
            get_kb_pressed,
            get_kb_released,
            get_kb_down,
        );

        if (self.idx < self.items.len) {
            const item: *const MenuItem = &self.items[@intCast(self.idx)];
            self.x_scroll.UpdateEx(
                item.idx,
                item.max,
                item.wrap,
                get_kb_pressed,
                get_kb_released,
                get_kb_down,
            );
        }

        const x = self.x;
        var y = self.y;
        var buf: [127:0]u8 = undefined;

        _ = std.fmt.bufPrintZ(&buf, "~f0~s{s}", .{self.title}) catch unreachable;
        rf.swrText_CreateEntry1(x, y, 255, 255, 255, 190, &buf);
        y += self.y_margin;

        var hl_i: i32 = 0;
        var hl_c: u8 = undefined;
        for (self.items) |item| {
            y += self.y_step;
            hl_c = if (self.idx == hl_i) self.hl_col else 1;
            _ = std.fmt.bufPrintZ(&buf, "~f4~{d}~s{s}", .{ hl_c, item.label }) catch unreachable;
            rf.swrText_CreateEntry1(x, y, 255, 255, 255, 190, &buf);
            _ = std.fmt.bufPrintZ(&buf, "~f4~s{s}", .{item.options[@intCast(item.idx.*)]}) catch unreachable;
            rf.swrText_CreateEntry1(x + self.x_step, y, 255, 255, 255, 190, &buf);
            hl_i += 1;
        }

        y += self.y_margin;
        if (self.confirm_fn) |f| {
            if (self.idx == hl_i and get_kb_pressed(self.confirm_key.?)) f();
            y += self.y_step;
            hl_c = if (self.idx == hl_i) self.hl_col else 1;
            const label = if (self.confirm_text) |t| t else "Confirm";
            _ = std.fmt.bufPrintZ(&buf, "~f4~{d}~s{s}", .{ hl_c, label }) catch unreachable;
            rf.swrText_CreateEntry1(x, y, 255, 255, 255, 190, &buf);
            hl_i += 1;
        }
        if (self.cancel_fn) |f| {
            if (self.idx == hl_i and get_kb_pressed(self.cancel_key.?)) f();
            y += self.y_step;
            hl_c = if (self.idx == hl_i) self.hl_col else 1;
            const label = if (self.cancel_text) |t| t else "Cancel";
            _ = std.fmt.bufPrintZ(&buf, "~f4~{d}~s{s}", .{ hl_c, label }) catch unreachable;
            rf.swrText_CreateEntry1(x, y, 255, 255, 255, 190, &buf);
            hl_i += 1;
        }
    }
};
