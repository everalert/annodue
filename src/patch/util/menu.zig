const Self = @This();

const std = @import("std");

const w32 = @import("zigwin32");
const w32kb = w32.ui.input.keyboard_and_mouse;

const MenuItem = @import("menu_item.zig").MenuItem;
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
        self.idx = self.y_scroll.UpdateEx(self.idx, self.max, self.wrap);
        if (self.idx != self.y_prev)
            rf.swrSound_PlaySoundMacro(88);

        if (self.idx < self.items.len) {
            var item: *MenuItem = @constCast(&self.items[@intCast(self.idx)]);
            if (item.value) |_| {
                self.x_prev = item.rval();
                item.rset(self.x_scroll.UpdateEx(item.rval(), item.rmax(), item.wrap));
                if (item.rval() != self.x_prev)
                    rf.swrSound_PlaySoundMacro(88);
            }
            if (item.callback) |cb| {
                if (cb(self))
                    rf.swrSound_PlaySoundMacro(88);
            }
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
        }
    }

    pub fn Draw(self: *Menu) void {
        const x1 = self.x - @divFloor(self.w, 2);
        const x2 = x1 + self.col_w;
        var y = self.y;

        rt.DrawText(@divFloor(self.x, 2), @divFloor(y, 2), "{s}", .{
            self.title,
        }, 0xFFFFFFFF, style_head) catch {};
        y += self.row_margin * 2;

        var hl_s: []const u8 = undefined;
        var hl_c: ?u32 = undefined;
        for (self.items, 0..) |item, i| {
            hl_s = if (self.idx == i) style_item_on else style_item_off;
            hl_c = if (self.idx == i) 0xFFFFFFFF else null;
            y += item.padding.t;
            if (item.label) |label| blk: {
                y += self.row_h;
                rt.DrawText(x1, y, "{s}", .{label}, hl_c, hl_s) catch {};
                if (item.value == null) break :blk;

                if (item.options) |o| {
                    rt.DrawText(x2, y, "{s}", .{o[@intCast(item.rval())]}, hl_c, hl_s) catch {};
                } else {
                    rt.DrawText(x2, y, "{d}", .{item.value.?.*}, hl_c, hl_s) catch {};
                }
            }
            y += item.padding.b;
        }
    }
};
