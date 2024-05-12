const std = @import("std");

const rf = @import("racer").functions;
const rc = @import("racer").constants;
const rt = @import("racer").text;
const re = @import("racer").Entity;
const rto = rt.TextStyleOpts;

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

        saved_pausebit = jdge.entity_flags & pausebit;
        saved_pausepage = mem.read(rc.ADDR_PAUSE_PAGE, u8);
        saved_pausestate = mem.read(rc.ADDR_PAUSE_STATE, u8);
        saved_pausescroll = mem.read(rc.ADDR_PAUSE_SCROLLINOUT, f32);

        _ = mem.write(rc.ADDR_PAUSE_PAGE, u8, 2);
        _ = mem.write(rc.ADDR_PAUSE_STATE, u8, 1);
        _ = mem.write(rc.ADDR_PAUSE_SCROLLINOUT, f32, 0);
        jdge.entity_flags &= ~pausebit;

        owner = o;
        frozen = true;
        return true;
    }

    /// @return request processed successfully
    pub fn unfreeze(o: [*:0]const u8) bool {
        const o_len = std.mem.len(o);
        if (!frozen or !std.mem.eql(u8, owner.?[0..o_len], o[0..o_len])) return false;
        var jdge = re.Manager.entity(.Jdge, 0);

        jdge.entity_flags |= saved_pausebit;
        _ = mem.write(rc.ADDR_PAUSE_SCROLLINOUT, f32, saved_pausescroll);
        _ = mem.write(rc.ADDR_PAUSE_STATE, u8, saved_pausestate);
        _ = mem.write(rc.ADDR_PAUSE_PAGE, u8, saved_pausepage);

        owner = null;
        frozen = false;
        return true;
    }

    /// @return game currently frozen via api
    pub fn is_frozen() bool {
        return frozen or owner != null;
    }
};
