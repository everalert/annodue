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

// FIXME: custom minimum value; need to update algorithm to impl
pub const MenuItem = struct {
    idx: *i32,
    wrap: bool = true,
    label: [*:0]const u8,
    options: ?[]const [*:0]const u8 = null,
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
    w: u16 = 320,
    x: u16 = 320,
    y: u16 = 128,
    col_w: u16 = 128,
    row_h: u16 = 10,
    row_margin: u16 = 8,
    x_scroll: ScrollControl,
    y_scroll: ScrollControl,
    hl_color: u8 = 3, // ingame predefined colors with ~{n}, default yellow

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

        const x1 = self.x - self.w / 2;
        const x2 = x1 + self.col_w;
        var y = self.y;
        var buf: [127:0]u8 = undefined;

        _ = std.fmt.bufPrintZ(&buf, "~f4~s~c{s}", .{self.title}) catch unreachable;
        rf.swrText_CreateEntry1(self.x / 2, y / 2, 255, 255, 255, 190, &buf);
        y += self.row_margin * 2;

        var hl_i: i32 = 0;
        var hl_c: u8 = undefined;
        for (self.items) |item| {
            y += self.row_h;
            hl_c = if (self.idx == hl_i) self.hl_color else 1;
            _ = std.fmt.bufPrintZ(&buf, "~F0~{d}~s{s}", .{ hl_c, item.label }) catch unreachable;
            rf.swrText_CreateEntry1(x1, y, 255, 255, 255, 190, &buf);
            _ = if (item.options) |options|
                std.fmt.bufPrintZ(&buf, "~F0~{d}~s{s}", .{ hl_c, options[@intCast(item.idx.*)] }) catch unreachable
            else
                // FIXME: number limits off by one when rawdogging
                std.fmt.bufPrintZ(&buf, "~F0~{d}~s{d}", .{ hl_c, item.idx.* }) catch unreachable;

            rf.swrText_CreateEntry1(x2, y, 255, 255, 255, 190, &buf);
            hl_i += 1;
        }

        y += self.row_margin;
        if (self.confirm_fn) |f| {
            if (self.idx == hl_i and get_kb_pressed(self.confirm_key.?)) f();
            y += self.row_h;
            hl_c = if (self.idx == hl_i) self.hl_color else 1;
            const label = if (self.confirm_text) |t| t else "Confirm";
            _ = std.fmt.bufPrintZ(&buf, "~F0~{d}~s{s}", .{ hl_c, label }) catch unreachable;
            rf.swrText_CreateEntry1(x1, y, 255, 255, 255, 190, &buf);
            hl_i += 1;
        }
        if (self.cancel_fn) |f| {
            if (self.idx == hl_i and get_kb_pressed(self.cancel_key.?)) f();
            y += self.row_h;
            hl_c = if (self.idx == hl_i) self.hl_color else 1;
            const label = if (self.cancel_text) |t| t else "Cancel";
            _ = std.fmt.bufPrintZ(&buf, "~F0~{d}~s{s}", .{ hl_c, label }) catch unreachable;
            rf.swrText_CreateEntry1(x1, y, 255, 255, 255, 190, &buf);
            hl_i += 1;
        }
    }
};
