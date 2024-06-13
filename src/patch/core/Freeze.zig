const std = @import("std");

const rg = @import("racer").Global;
const re = @import("racer").Entity;

const mem = @import("../util/memory.zig");

// TODO: turn off race HUD when freezing
// TODO: turn off/fade out other displays when freezing? e.g. savestate, overlay

pub const Freeze = extern struct {
    const pausebit: u32 = 1 << 28;
    var frozen: bool = false;
    var owner: ?[*:0]const u8 = null;
    var saved_pausebit: usize = undefined;
    var saved_pausepage: u8 = undefined;
    var saved_pausestate: u8 = undefined;
    var saved_pausescroll: f32 = undefined;

    /// @return request processed successfully
    pub fn freeze(o: [*:0]const u8) bool {
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

    /// @return request processed successfully
    pub fn unfreeze(o: [*:0]const u8) bool {
        const o_len = std.mem.len(o);
        if (!frozen or !std.mem.eql(u8, owner.?[0..o_len], o[0..o_len])) return false;
        var jdge = re.Manager.entity(.Jdge, 0);

        jdge.EntityFlags |= saved_pausebit;
        rg.PAUSE_SCROLLINOUT.* = saved_pausescroll;
        rg.PAUSE_STATE.* = saved_pausestate;
        rg.PAUSE_PAGE.* = saved_pausepage;

        owner = null;
        frozen = false;
        return true;
    }

    /// @return game currently frozen via api
    pub fn is_frozen() bool {
        return frozen or owner != null;
    }
};
