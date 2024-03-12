const Self = @This();

const std = @import("std");

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;

const ScrollControl = @import("scroll_control.zig").ScrollControl;
const st = @import("active_state.zig");
const input = @import("input.zig");
const r = @import("racer.zig");
const rc = r.constants;
const rf = r.functions;
const rt = r.text;
const rto = rt.TextStyleOpts;

// TODO: scrolling menu when the menu is too long to fit on screen

pub const InputGetFnType = *const fn (st.ActiveState) callconv(.C) bool;
pub const MenuItemCallbackType = *const fn (*Menu) callconv(.C) void;

pub const MenuItem = struct {
    value: ?*i32 = null, // if null, item will be skipped when scrolling through menu
    label: ?[]const u8 = null,
    options: ?[]const []const u8 = null,
    min: i32 = 0,
    max: i32,
    padding: struct {
        t: i16 = 0,
        b: i16 = 0,
        l: i16 = 0,
        r: i16 = 0,
    } = .{},
    wrap: bool = true,
    callback: ?MenuItemCallbackType = null,

    fn rset(self: *MenuItem, value: i32) void {
        if (self.value) |v| v.* = value + self.min;
    }

    fn rval(self: *const MenuItem) i32 {
        return if (self.value) |v| v.* - self.min else 0;
    }

    fn rmax(self: *const MenuItem) i32 {
        const m: i32 = self.max - self.min;
        return if (self.options) |_| m else m + 1;
    }
};

const menu_item_toggle_opts = [_][]const u8{ "Off", "On" };

pub inline fn MenuItemHeader(label: []const u8) MenuItem {
    return .{
        .label = label,
        .padding = .{
            .t = 8,
            .b = 4,
        },
        .max = 0,
    };
}

pub inline fn MenuItemSpacer() MenuItem {
    return .{
        .padding = .{
            .b = 4,
        },
        .max = 0,
    };
}

pub inline fn MenuItemButton(label: []const u8, callback: MenuItemCallbackType) MenuItem {
    return .{
        .label = label,
        .callback = callback,
        .max = 0,
    };
}

pub inline fn MenuItemToggle(
    value: *i32,
    label: []const u8,
) MenuItem {
    return .{
        .value = value,
        .label = label,
        .options = &menu_item_toggle_opts,
        .max = 2,
    };
}

pub inline fn MenuItemRange(
    value: *i32,
    label: []const u8,
    min: i32,
    max: i32,
    wrap: bool,
) MenuItem {
    return .{
        .value = value,
        .label = label,
        .min = min,
        .max = max,
        .wrap = wrap,
    };
}

pub inline fn MenuItemList(
    value: *i32,
    label: []const u8,
    options: []const []const u8,
    wrap: bool,
) MenuItem {
    return .{
        .value = value,
        .label = label,
        .options = options,
        .max = options.len,
        .wrap = wrap,
    };
}

// TODO: play menu sounds, e.g. when scrolling
// TODO: a way to quick confirm, so you don't have to scroll to the confirm item
pub const Menu = struct {
    const style_head = rt.MakeTextHeadStyle(.Small, false, null, .Center, .{
        rto.ToggleShadow,
    }) catch "";
    const style_item_on = rt.MakeTextHeadStyle(.Default, true, .Yellow, null, .{
        rto.ToggleShadow,
    }) catch "";
    const style_item_off = rt.MakeTextHeadStyle(.Default, true, .White, null, .{
        rto.ToggleShadow,
    }) catch "";

    idx: i32 = 0,
    wrap: bool = true,
    title: [*:0]const u8,
    items: []const MenuItem,
    max: i32,
    //confirm_fn: ?*fn () void = null,
    confirm_key: ?InputGetFnType = null,
    w: i16 = 320,
    x: i16 = 320,
    y: i16 = 128,
    col_w: i16 = 128,
    row_h: i16 = 10,
    row_margin: i16 = 8,
    x_scroll: ScrollControl,
    y_scroll: ScrollControl,
    //hl_color: rt.Color = .Yellow, // FIXME: not in use due to text api needing comptime

    pub fn UpdateAndDrawEx(self: *Menu) void {
        self.idx = self.y_scroll.UpdateEx(self.idx, self.max, self.wrap);

        if (self.idx < self.items.len) {
            var item: *MenuItem = @constCast(&self.items[@intCast(self.idx)]);
            if (item.value) |_|
                item.rset(self.x_scroll.UpdateEx(item.rval(), item.rmax(), item.wrap));
        }

        var last_real: u32 = 0;
        for (self.items, 0..) |item, i| {
            if (item.value != null or item.callback != null)
                last_real = i;
            if (item.value == null and item.callback == null and self.idx == i) {
                // TODO: something more sophisticated, that allows quickly switching up/down
                // FIXME: probably a bug when trying to scroll the extents with a blank item there
                if (self.y_scroll.input_dec(.On) or self.y_scroll.input_dec(.JustOn))
                    self.idx = @intCast(last_real);
                if (self.y_scroll.input_inc(.On) or self.y_scroll.input_inc(.JustOn))
                    self.idx += 1;
            }
            if (item.callback != null and self.idx == i) item.callback.?(self);
        }

        const x1 = self.x - @divFloor(self.w, 2);
        const x2 = x1 + self.col_w;
        var y = self.y;

        rt.DrawText(@divFloor(self.x, 2), @divFloor(y, 2), "{s}", .{
            self.title,
        }, null, style_head) catch {};
        y += self.row_margin * 2;

        var hl_s: []const u8 = undefined;
        for (self.items, 0..) |item, i| {
            hl_s = if (self.idx == i) style_item_on else style_item_off;
            y += item.padding.t;
            if (item.label) |label| blk: {
                y += self.row_h;
                rt.DrawText(x1, y, "{s}", .{label}, null, hl_s) catch {};
                if (item.value == null) break :blk;

                if (item.options) |options| {
                    rt.DrawText(x2, y, "{s}", .{
                        options[@intCast(item.rval())],
                    }, null, hl_s) catch {};
                } else {
                    rt.DrawText(x2, y, "{d}", .{item.value.?.*}, null, hl_s) catch {};
                }
            }
            y += item.padding.b;
        }
    }
};
