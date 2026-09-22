const std = @import("std");

const PluginAPI = @import("../util/root.zig").PluginAPI;

const WorkingOwner = @import("AHook.zig").PluginState.WorkingOwner;

const rq = @import("racer").Quad;
const rg = @import("racer").Global;

const mem = @import("../util/memory.zig");
const ToggleState = @import("../util/toggle_state.zig").ToggleState;
const plugh = @import("../util/plugin/plugin_helper.zig");
const RAddressHandleInfo = plugh.RAddressHandleInfo;
const RAddressHandle = @import("../util/plugin/plugin.zig").RAddressHandle;

// FIXME: resolve clashing with practice mode indicators (should not hide them
// even when everything else is). also makes lighting effects disappear
// TODO: check with LP if there is a different way of hiding race UI

pub const HideRaceUI = extern struct {
    var hidden: bool = false;
    var owner: ?u16 = null;

    var paused: ToggleState = .On; // force .JustOff on first frame

    var h_ar_hide = RAddressHandleInfo.InitLen(0x463580, 1);
    var h_ar_quadskip = RAddressHandleInfo.InitLen(@intFromPtr(rq.QUAD_SKIP_RENDERING), 4);

    var api: *PluginAPI = undefined;

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
        if (disable and !api.SInRace().on()) return;

        const handles = [_]RAddressHandle{ h_ar_hide.Handle, h_ar_quadskip.Handle };
        if (!plugh.RAddressPatchToggleGroup(api, &handles, disable)) return;

        _ = plugh.RAddressRangeWrite(api, handles[0], 0x463580, u8, 0xC3); // insert RETN at top of Jdge0x20
        rq.QUAD_SKIP_RENDERING.* = @intFromBool(disable);
    }
};

// GLOBAL EXPORTS

/// @return request processed successfully
pub fn GHideRaceUIOn() callconv(.C) bool {
    return HideRaceUI.hide(WorkingOwner());
}

/// @return request processed successfully
pub fn GHideRaceUIOff() callconv(.C) bool {
    return HideRaceUI.unhide(WorkingOwner());
}

/// @return game currently hiding race ui via api
pub fn GHideRaceUIIsOn() callconv(.C) bool {
    return HideRaceUI.hidden or HideRaceUI.owner != null;
}

// HOOKS

pub fn OnInit(api: *PluginAPI) callconv(.C) void {
    // FIXME: don't do this
    HideRaceUI.api = api;

    HideRaceUI.h_ar_hide.Reserve(api);
    HideRaceUI.h_ar_quadskip.Reserve(api);
}

pub fn OnInitLate(_: *PluginAPI) callconv(.C) void {}

pub fn OnDeinit(_: *PluginAPI) callconv(.C) void {
    if (HideRaceUI.owner) |o|
        _ = HideRaceUI.unhide(o);
}

pub fn EarlyEngineUpdateB(gf: *PluginAPI) callconv(.C) void {
    HideRaceUI.paused.update(rg.PAUSE_STATE.* > 0);
    if (!HideRaceUI.hidden) return;

    if (HideRaceUI.paused == .JustOff)
        HideRaceUI.writeHide(true);

    switch (gf.SInRace()) {
        .JustOn => HideRaceUI.writeHide(true),
        .JustOff => HideRaceUI.writeHide(false),
        else => {},
    }
}

pub fn OnPluginDeinitA(owner: u16) callconv(.C) void {
    if (HideRaceUI.owner == owner)
        _ = HideRaceUI.unhide(owner);
}
