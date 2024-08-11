const std = @import("std");

const app = @import("../appinfo.zig");
const GlobalSt = app.GLOBAL_STATE;
const GlobalFn = app.GLOBAL_FUNCTION;
const GLOBAL_STATE = &@import("Global.zig").GLOBAL_STATE;
const workingOwner = @import("Hook.zig").PluginState.workingOwner;

const rq = @import("racer").Quad;
const rg = @import("racer").Global;

const mem = @import("../util/memory.zig");
const ActiveState = @import("../util/active_state.zig").ActiveState;

// FIXME: resolve clashing with practice mode indicators (should not hide them
// even when everything else is). also makes lighting effects disappear
// TODO: check with LP if there is a different way of hiding race UI

pub const HideRaceUI = extern struct {
    var hidden: bool = false;
    var owner: ?u16 = null;

    var paused: ActiveState = .On; // force .JustOff on first frame

    pub fn hide(o: u16) bool {
        if (hidden or owner != null) return false;
        writeHide(true);
        owner = o;
        hidden = true;
        return true;
    }

    pub fn unhide(o: u16) bool {
        if (!hidden or owner != o) return false;
        writeHide(false);
        owner = null;
        hidden = false;
        return true;
    }

    inline fn writeHide(disable: bool) void {
        if (disable and !GLOBAL_STATE.in_race.on()) return;

        const instruction: u8 = if (disable) 0xC3 else 0x81; // RETN or original value
        _ = mem.write(0x463580, u8, instruction); // top of Jdge0x20
        rq.QUAD_SKIP_RENDERING.* = @intFromBool(disable);
    }
};

// GLOBAL EXPORTS

/// @return request processed successfully
pub fn GHideRaceUIOn() bool {
    return HideRaceUI.hide(workingOwner());
}

/// @return request processed successfully
pub fn GHideRaceUIOff() bool {
    return HideRaceUI.unhide(workingOwner());
}

/// @return game currently hiding race ui via api
pub fn GHideRaceUIIsOn() bool {
    return HideRaceUI.hidden or HideRaceUI.owner != null;
}

// HOOKS

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    if (HideRaceUI.owner) |o|
        _ = HideRaceUI.unhide(o);
}

pub fn EarlyEngineUpdateB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    HideRaceUI.paused.update(rg.PAUSE_STATE.* > 0);
    if (!HideRaceUI.hidden) return;

    if (HideRaceUI.paused == .JustOff)
        HideRaceUI.writeHide(true);

    switch (gs.in_race) {
        .JustOn => HideRaceUI.writeHide(true),
        .JustOff => HideRaceUI.writeHide(false),
        else => {},
    }
}

pub fn OnPluginDeinitA(owner: u16) callconv(.C) void {
    if (HideRaceUI.owner == owner)
        _ = HideRaceUI.unhide(owner);
}
