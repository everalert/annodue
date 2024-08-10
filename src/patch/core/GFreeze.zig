const std = @import("std");

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;
const workingOwner = @import("Hook.zig").PluginState.workingOwner;

const mem = @import("../util/memory.zig");

const rg = @import("racer").Global;
const re = @import("racer").Entity;

// TODO: turn off race HUD when freezing
// TODO: turn off/fade out other displays when freezing? e.g. savestate, overlay

pub const Freeze = extern struct {
    const pausebit: u32 = 1 << 28;
    var frozen: bool = false;
    var owner: ?u16 = null;
    var saved_pausebit: usize = undefined;
    var saved_pausepage: u8 = undefined;
    var saved_pausestate: u8 = undefined;
    var saved_pausescroll: f32 = undefined;

    pub fn freeze(o: u16) bool {
        if (frozen or owner != null) return false;
        var jdge = re.Manager.entity(.Jdge, 0);

        saved_pausebit = jdge.EntityFlags & pausebit;
        saved_pausepage = rg.PAUSE_PAGE.*;
        saved_pausestate = rg.PAUSE_STATE.*;
        saved_pausescroll = rg.PAUSE_SCROLLINOUT.*;

        rg.PAUSE_PAGE.* = 2;
        rg.PAUSE_STATE.* = 1;
        rg.PAUSE_SCROLLINOUT.* = 0;
        jdge.EntityFlags &= ~pausebit;

        owner = o;
        frozen = true;
        return true;
    }

    pub fn unfreeze(o: u16) bool {
        if (!frozen or owner != o) return false;
        var jdge = re.Manager.entity(.Jdge, 0);

        jdge.EntityFlags |= saved_pausebit;
        rg.PAUSE_SCROLLINOUT.* = saved_pausescroll;
        rg.PAUSE_STATE.* = saved_pausestate;
        rg.PAUSE_PAGE.* = saved_pausepage;

        owner = null;
        frozen = false;
        return true;
    }
};

// GLOBAL EXPORTS

/// @return request processed successfully
pub fn GFreezeOn() bool {
    return Freeze.freeze(workingOwner());
}

/// @return request processed successfully
pub fn GFreezeOff() bool {
    return Freeze.unfreeze(workingOwner());
}

/// @return game currently frozen via api
pub fn GFreezeIsOn() bool {
    return Freeze.frozen or Freeze.owner != null;
}

// HOOKS

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    if (Freeze.owner) |o|
        _ = Freeze.unfreeze(o);
}

pub fn OnPluginDeinitA(owner: u16) callconv(.C) void {
    if (Freeze.owner == owner)
        _ = Freeze.unfreeze(owner);
}
