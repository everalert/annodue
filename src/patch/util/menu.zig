const Self = @This();

const std = @import("std");

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;

const ScrollControl = @import("scroll_control.zig").ScrollControl;
const st = @import("toggle_state.zig");

const r = @import("racer");
const rt = r.Text;
const rso = r.Sound;
const rto = rt.TextStyleOpts;

// FIXME: migrate to sentinel-terminated slice string types
// TODO: scrolling menu when the menu is too long to fit on screen
// TODO: convert menus to GDraw (after core menu system impl)

pub const InputGetFnType = *const fn (st.ToggleState) callconv(.C) bool;

/// @return     whether or not to play sound effect
pub const MenuCallbackType = *const fn (*Menu) callconv(.C) bool;

/// @return     whether or not to play sound effect
pub const MenuItemCallbackType = *const fn (*Menu, *MenuItem) callconv(.C) bool;

pub const Menu = extern struct {
    const style_head = rt.hMakeTextHeadStyle(.Small, false, null, .Center, .{rto.ToggleShadow}) catch "";
    const style_item_on = rt.hMakeTextHeadStyle(.Default, true, .Yellow, null, .{rto.ToggleShadow}) catch "";
    const style_item_off = rt.hMakeTextHeadStyle(.Default, true, .White, null, .{rto.ToggleShadow}) catch "";

    idx: i32 = 0,
    wrap: bool = true,
    title: [*:0]const u8,
    items: extern struct {
        it: [*]const MenuItem,
        len: i32,
    },
    inputs: extern struct {
        cb: ?[*]const InputGetFnType = null,
        len: i32 = 0,
    } = .{},
    callback: ?MenuCallbackType = null,
    w: i16 = 320,
    x: i16 = 320,
    y: i16 = 128,
    col_w: i16 = 128,
    row_h: i16 = 10,
    row_margin: i16 = 8,
    x_scroll: ScrollControl,
    x_prev: i32 = 0,
    y_scroll: ScrollControl,
    y_prev: i32 = 0,
    //hl_color: rt.Color = .Yellow, // FIXME: not in use due to text api needing comptime

    pub fn UpdateAndDraw(self: *Menu) void {
        self.Update();
        self.Draw();
    }

    pub fn Update(self: *Menu) void {
        self.y_prev = self.idx;
        self.idx = self.y_scroll.UpdateEx(self.idx, self.items.len, self.wrap);
        if (self.idx != self.y_prev)
            rso.swrSound_PlaySoundMacro(88);
        if (self.callback) |cb| {
            if (cb(self))
                rso.swrSound_PlaySoundMacro(88);
        }

        if (self.idx < self.items.len) {
            var item: *MenuItem = @constCast(&self.items.it[@intCast(self.idx)]);
            if (item.value) |_| {
                self.x_prev = item.rval();
                item.rset(self.x_scroll.UpdateEx(item.rval(), item.rmax(), item.wrap));
                if (item.rval() != self.x_prev)
                    rso.swrSound_PlaySoundMacro(88);
            }
            if (item.callback) |cb| {
                if (cb(self, item))
                    rso.swrSound_PlaySoundMacro(88);
            }
        }

        var last_real: u32 = 0;
        for (0..@intCast(self.items.len)) |i| {
            const item = self.items.it[i];
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
        }
    }

    pub fn Draw(self: *Menu) void {
        const x1 = self.x - @divFloor(self.w, 2);
        const x2 = x1 + self.col_w;
        var y = self.y;

        rt.hDrawText(@divFloor(self.x, 2), @divFloor(y, 2), "{s}", .{
            self.title,
        }, 0xFFFFFFFF, style_head) catch {};
        y += self.row_margin * 2;

        var hl_s: []const u8 = undefined;
        var hl_c: ?u32 = undefined;
        for (0..@intCast(self.items.len)) |i| {
            const item = self.items.it[i];
            hl_s = if (self.idx == i) style_item_on else style_item_off;
            hl_c = if (self.idx == i) 0xFFFFFFFF else null;
            y += item.padding.t;
            if (item.label) |label| blk: {
                y += self.row_h;
                rt.hDrawText(x1, y, "{s}", .{label}, hl_c, hl_s) catch {};
                if (item.value == null) break :blk;

                if (item.options) |o| {
                    rt.hDrawText(x2, y, "{s}", .{o[@intCast(item.rval())]}, hl_c, hl_s) catch {};
                } else {
                    rt.hDrawText(x2, y, "{d}", .{item.value.?.*}, hl_c, hl_s) catch {};
                }
            }
            y += item.padding.b;
        }
    }
};

pub const MenuItem = extern struct {
    value: ?*i32 = null,
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
    callback: ?MenuItemCallbackType,
) MenuItem {
    return .{
        .value = value,
        .label = label,
        .options = &menu_item_toggle_opts,
        .max = 2,
        .callback = callback,
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
