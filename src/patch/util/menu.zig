const Self = @This();

const std = @import("std");

const win32 = @import("zigwin32");
const win32kb = win32.ui.input.keyboard_and_mouse;

const ScrollControl = @import("scroll_control.zig").ScrollControl;
const input = @import("input.zig");
const r = @import("racer.zig");
const rc = r.constants;
const rf = r.functions;
const rt = r.text;
const rto = rt.TextStyleOpts;

const InputGetFnType = *const @TypeOf(input.get_kb_pressed);

// FIXME: custom minimum value; need to update algorithm to impl
pub const MenuItem = struct {
    idx: *i32,
    wrap: bool = true,
    label: []const u8,
    options: ?[]const []const u8 = null,
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
    w: i16 = 320,
    x: i16 = 320,
    y: i16 = 128,
    col_w: i16 = 128,
    row_h: i16 = 10,
    row_margin: i16 = 8,
    x_scroll: ScrollControl,
    y_scroll: ScrollControl,
    hl_color: rt.Color = .Yellow, // FIXME: not in use due to text api needing comptime
    const style_head = rt.MakeTextHeadStyle(.Small, false, null, .Center, .{rto.ToggleShadow}) catch "";
    const style_item_on = rt.MakeTextHeadStyle(.Default, true, .Yellow, null, .{rto.ToggleShadow}) catch "";
    const style_item_off = rt.MakeTextHeadStyle(.Default, true, .White, null, .{rto.ToggleShadow}) catch "";

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

        const x1 = self.x - @divFloor(self.w, 2);
        const x2 = x1 + self.col_w;
        var y = self.y;

        rt.DrawText(@divFloor(self.x, 2), @divFloor(y, 2), "{s}", .{self.title}, null, style_head) catch {};
        y += self.row_margin * 2;

        var hl_i: i32 = 0;
        var hl_s: []const u8 = undefined;
        for (self.items) |item| {
            y += self.row_h;
            hl_s = if (self.idx == hl_i) style_item_on else style_item_off;
            rt.DrawText(x1, y, "{s}", .{item.label}, null, hl_s) catch {};
            if (item.options) |options| {
                rt.DrawText(x2, y, "{s}", .{options[@intCast(item.idx.*)]}, null, hl_s) catch {};
            } else {
                // FIXME: number limits off by one when rawdogging
                rt.DrawText(x2, y, "{d}", .{item.idx.*}, null, hl_s) catch {};
            }
            hl_i += 1;
        }

        y += self.row_margin;
        if (self.confirm_fn) |f| {
            if (self.idx == hl_i and get_kb_pressed(self.confirm_key.?)) f();
            y += self.row_h;
            hl_s = if (self.idx == hl_i) style_item_on else style_item_off;
            const label = if (self.confirm_text) |t| t else "Confirm";
            rt.DrawText(x1, y, "{s}", .{label}, null, hl_s) catch {};
            hl_i += 1;
        }
        if (self.cancel_fn) |f| {
            if (self.idx == hl_i and get_kb_pressed(self.cancel_key.?)) f();
            y += self.row_h;
            hl_s = if (self.idx == hl_i) style_item_on else style_item_off;
            const label = if (self.cancel_text) |t| t else "Cancel";
            rt.DrawText(x1, y, "{s}", .{label}, null, hl_s) catch {};
            hl_i += 1;
        }
    }
};
