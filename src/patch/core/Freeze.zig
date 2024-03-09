const std = @import("std");

const r = @import("../util/racer.zig");
const rf = r.functions;
const rc = r.constants;
const rt = r.text;
const rto = rt.TextStyleOpts;

const mem = @import("../util/memory.zig");

// FIXME: also probably need to start thinking about making a distinction
// between global state and game manipulation functions
// TODO: turn off race HUD when freezing

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
        const pauseflags = r.ReadEntityValue(.Jdge, 0, 0x04, u32);

        saved_pausebit = pauseflags & pausebit;
        saved_pausepage = mem.read(rc.ADDR_PAUSE_PAGE, u8);
        saved_pausestate = mem.read(rc.ADDR_PAUSE_STATE, u8);
        saved_pausescroll = mem.read(rc.ADDR_PAUSE_SCROLLINOUT, f32);

        _ = mem.write(rc.ADDR_PAUSE_PAGE, u8, 2);
        _ = mem.write(rc.ADDR_PAUSE_STATE, u8, 1);
        _ = mem.write(rc.ADDR_PAUSE_SCROLLINOUT, f32, 0);
        _ = r.WriteEntityValue(.Jdge, 0, 0x04, u32, pauseflags & ~pausebit);

        owner = o;
        frozen = true;
        return true;
    }

    /// @return request processed successfully
    pub fn unfreeze(o: [*:0]const u8) bool {
        const o_len = std.mem.len(o);
        if (!frozen or !std.mem.eql(u8, owner.?[0..o_len], o[0..o_len])) return false;
        const pauseflags = r.ReadEntityValue(.Jdge, 0, 0x04, u32);

        r.WriteEntityValue(.Jdge, 0, 0x04, u32, pauseflags | saved_pausebit);
        _ = mem.write(rc.ADDR_PAUSE_SCROLLINOUT, f32, saved_pausescroll);
        _ = mem.write(rc.ADDR_PAUSE_STATE, u8, saved_pausestate);
        _ = mem.write(rc.ADDR_PAUSE_PAGE, u8, saved_pausepage);

        owner = null;
        frozen = false;
        return true;
    }
};
