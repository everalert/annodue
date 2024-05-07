const Self = @This();

const std = @import("std");

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;

const Menu = @import("menu.zig").Menu;
const ScrollControl = @import("scroll_control.zig").ScrollControl;
const st = @import("active_state.zig");
const input = @import("../core/input.zig");

const r = @import("racer.zig");
const rc = r.constants;
const rf = r.functions;
const rt = r.text;
const rto = rt.TextStyleOpts;

pub const MenuItemCallbackType = *const fn (*Menu) callconv(.C) bool;

pub const MenuItem = extern struct {
    value: ?*i32 = null, // if null, item will be skipped when scrolling through menu
    label: ?[*:0]const u8 = null,
    options: ?[*]const [*:0]const u8 = null,
    min: i32 = 0,
    max: i32,
    padding: extern struct {
        t: i16 = 0,
        b: i16 = 0,
        l: i16 = 0,
        r: i16 = 0,
    } = .{},
    wrap: bool = true,
    callback: ?MenuItemCallbackType = null,

    pub fn rset(self: *MenuItem, value: i32) void {
        if (self.value) |v| v.* = value + self.min;
    }

    pub fn rval(self: *const MenuItem) i32 {
        return if (self.value) |v| v.* - self.min else 0;
    }

    pub fn rmax(self: *const MenuItem) i32 {
        const m: i32 = self.max - self.min;
        return if (self.options) |_| m else m + 1;
    }
};

const menu_item_toggle_opts = [_][*:0]const u8{ "Off", "On" };

pub inline fn MenuItemHeader(
    label: [*:0]const u8,
) MenuItem {
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

pub inline fn MenuItemButton(
    label: [*:0]const u8,
    callback: MenuItemCallbackType,
) MenuItem {
    return .{
        .label = label,
        .callback = callback,
        .max = 0,
    };
}

pub inline fn MenuItemToggle(
    value: *i32,
    label: [*:0]const u8,
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
    label: [*:0]const u8,
    min: i32,
    max: i32,
    wrap: bool,
    callback: ?MenuItemCallbackType,
) MenuItem {
    return .{
        .value = value,
        .label = label,
        .min = min,
        .max = max,
        .wrap = wrap,
        .callback = callback,
    };
}

pub inline fn MenuItemList(
    value: *i32,
    label: [*:0]const u8,
    options: []const [*:0]const u8,
    wrap: bool,
    callback: ?MenuItemCallbackType,
) MenuItem {
    return .{
        .value = value,
        .label = label,
        .options = @ptrCast(&options[0]),
        .max = options.len,
        .wrap = wrap,
        .callback = callback,
    };
}
