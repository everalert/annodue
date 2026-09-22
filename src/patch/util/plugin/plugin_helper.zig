const std = @import("std");
const assert = std.debug.assert;

const plug = @import("plugin.zig");
const PluginAPI = plug.PluginAPI;

const ToggleState = @import("../toggle_state.zig").ToggleState;

//------------------------------------------------------------------------------
// AMemory

pub inline fn AMemoryGetPermanentT(gf: *PluginAPI, comptime T: type) ?*T {
    return @as(*T, @ptrCast(@alignCast(gf.AMemoryGetPermanent(@sizeOf(T)) orelse return null)));
}

pub inline fn AMemoryGetPermanentZeroT(gf: *PluginAPI, comptime T: type) ?*T {
    return @as(*T, @ptrCast(@alignCast(gf.AMemoryGetPermanentZero(@sizeOf(T)) orelse return null)));
}

pub inline fn AMemoryGetTemporaryT(gf: *PluginAPI, comptime T: type) ?*T {
    return @as(*T, @ptrCast(@alignCast(gf.AMemoryGetTemporary(@sizeOf(T)) orelse return null)));
}

pub inline fn AMemoryGetTemporaryZeroT(gf: *PluginAPI, comptime T: type) ?*T {
    return @as(*T, @ptrCast(@alignCast(gf.AMemoryGetTemporaryZero(@sizeOf(T)) orelse return null)));
}

//------------------------------------------------------------------------------
// RAddress

const RAddressHandle = plug.RAddressHandle;
const RADDRESS_HANDLE_NULL = plug.RADDRESS_HANDLE_NULL;

// TODO: reservation for common types of memory that figure out the end address
//  for you, e.g. addr+5 bytes for a callsite
// TODO: helper that allocs both an address range and permanent memory at the
//  same time as a convenience for setting up detour code

/// convenience struct for cutting down on definitions
pub const RAddressHandleInfo = struct {
    Handle: RAddressHandle,
    AddrSt: u32,
    AddrEd: u32,

    pub fn Init(addr_st: u32, addr_ed: u32) RAddressHandleInfo {
        assert(addr_ed > addr_st);
        return RAddressHandleInfo{
            .Handle = RADDRESS_HANDLE_NULL,
            .AddrSt = addr_st,
            .AddrEd = addr_ed,
        };
    }

    pub fn InitLen(addr: u32, len: u32) RAddressHandleInfo {
        return Init(addr, addr + len);
    }

    pub fn Reserve(self: *RAddressHandleInfo, gf: *PluginAPI) void {
        self.Handle = gf.RAddressRangeReserve(self.AddrSt, self.AddrEd);
    }
};

/// returns `true` if range was reserved and its handle written to @handle_out
pub fn RAddressRangeReserveIfAvailable(gf: *PluginAPI, addr_st: u32, addr_ed: u32) RAddressHandle {
    const b_available = gf.RAddressRangeAvailable(addr_st, addr_ed);
    return if (b_available) gf.RAddressRangeReserve(addr_st, addr_ed) else RADDRESS_HANDLE_NULL;
}

pub fn RAddressRangeWrite(gf: *PluginAPI, handle: RAddressHandle, addr: u32, comptime T: type, val: T) bool {
    assert(gf.RAddressRangeContainsRange(handle, addr, addr + @sizeOf(T)));
    if (!gf.RAddressRangeWriteSt(handle)) return false;
    defer gf.RAddressRangeWriteEd(handle);

    const data: []const u8 = @as([*]const u8, @ptrCast(&val))[0..@sizeOf(T)];
    @memcpy(@as([*]u8, @ptrFromInt(addr)), data);
    return true;
}

pub fn RAddressRangeWriteBytes(gf: *PluginAPI, handle: RAddressHandle, addr: u32, buf: []const u8) bool {
    assert(gf.RAddressRangeContainsRange(handle, addr, addr + buf.len));
    if (!gf.RAddressRangeWriteSt(handle)) return false;
    defer gf.RAddressRangeWriteEd(handle);

    @memcpy(@as([*]u8, @ptrFromInt(addr)), buf);
    return true;
}

/// helper to apply or revert a memory patch that has a simple on-off pattern
/// where disabling the patch only involves reverting the game memory to its
/// original state. user should use this as a "guard" to doing the enable action.
/// if the function succeeds, the user should do the "enable" action; if the
/// function fails, the user should do nothing, and the memory reversion is
/// implicit in the disable case.
/// @return  whether the calling function should abort the "enable" action
pub fn RAddressPatchToggle(gf: *PluginAPI, handle: RAddressHandle, enable: bool) bool {
    if (handle == RADDRESS_HANDLE_NULL) return false;
    if (enable) return true;
    gf.RAddressRangeRestore(handle);
    return false;
}

/// same as `RAddressPatchToggle` but applies to a whole group collectively, performing
/// no action if any of the handles are invalid
pub fn RAddressPatchToggleGroup(gf: *PluginAPI, handles: []const RAddressHandle, enable: bool) bool {
    for (handles) |handle| if (handle == RADDRESS_HANDLE_NULL) return false;
    if (enable) return true;
    for (handles) |handle| gf.RAddressRangeRestore(handle);
    return false;
}

//------------------------------------------------------------------------------
// AInput

const AInputVirtualKey = plug.AInputVirtualKey;
const AInputXInputAxis = plug.AInputXInputAxis;
const AInputXInputButton = plug.AInputXInputButton;

// TODO: add 'dominant' field, as a way of communicating which device is 'active'
/// abstract interface for a single input. used mainly for reading a group of
/// inputs as a single input, such as when multiple physical inputs map to the
/// same logical input.
pub const AInputMap = struct {
    pCtx: *anyopaque,
    ValueSt: ?*ToggleState = null,
    ValueF: ?*f32 = null,
    fnUpdate: *const fn (ptr: *anyopaque, gf: *PluginAPI) void,

    pub fn Update(self: *AInputMap, gf: *PluginAPI) void {
        self.fnUpdate(self.pCtx, gf);
    }

    pub fn GetSt(self: *AInputMap) ToggleState {
        return if (self.ValueSt) |v| v.* else .Off;
    }

    pub fn GetF(self: *AInputMap) f32 {
        return if (self.ValueF) |v| v.* else 0;
    }
};

// TODO: StickInputMap, with deadzone inbuilt, and remove kb_scale in lieu of 'dominant' field on InputMap

// TODO: inbuilt deadzone, remove kb_scale in lieu of 'dominant' field on InputMap
/// map for combining keyboard keys and (an) xinput axis as sources for a single "axis" input
pub const AInputAxisMap = struct {
    State: f32 = 0,
    KbDec: ?AInputVirtualKey = null,
    KbInc: ?AInputVirtualKey = null,
    KbScale: f32 = 1,
    XiDec: ?AInputXInputAxis = null,
    XiInc: ?AInputXInputAxis = null,

    fn Update(ctx: *anyopaque, gf: *PluginAPI) void {
        const self: *AInputAxisMap = @ptrCast(@alignCast(ctx));

        const kb_dec: f32 = if (self.KbDec) |k| @floatFromInt(@intFromBool(gf.AInputKbGetRaw(k).on())) else 0;
        const kb_inc: f32 = if (self.KbInc) |k| @floatFromInt(@intFromBool(gf.AInputKbGetRaw(k).on())) else 0;
        const xi_dec: f32 = if (self.XiDec) |x| gf.AInputXInputGetAxis(x) else 0;
        const xi_inc: f32 = if (self.XiInc) |x| gf.AInputXInputGetAxis(x) else 0;

        self.State = std.math.clamp(xi_inc - xi_dec + (kb_inc - kb_dec) * self.KbScale, -1, 1);

        // NOTE: device-dominant version
        //const kb: f32 = std.math.clamp((kb_inc - kb_dec) * self.kb_scale, -1, 1);
        //const xi: f32 = std.math.clamp(xi_inc - xi_dec, -1, 1);
        //self.state = if (@fabs(kb) > @fabs(xi)) kb else xi;
    }

    pub fn InputMap(self: *AInputAxisMap) AInputMap {
        return .{
            .pCtx = self,
            .ValueF = &self.State,
            .fnUpdate = Update,
        };
    }
};

/// map for combining a keyboard key and an xinput button as sources for a "button" input
pub const AInputButtonMap = struct {
    State: ToggleState = .Off,
    Kb: ?AInputVirtualKey = null,
    Xi: ?AInputXInputButton = null,

    fn Update(ctx: *anyopaque, gf: *PluginAPI) void {
        const self: *AInputButtonMap = @ptrCast(@alignCast(ctx));

        const kb: bool = if (self.Kb) |k| gf.AInputKbGetRaw(k).on() else false;
        const xi: bool = if (self.Xi) |x| gf.AInputXInputGetButton(x).on() else false;

        self.State.update(kb or xi);
    }

    pub fn InputMap(self: *AInputButtonMap) AInputMap {
        return .{
            .pCtx = self,
            .ValueSt = &self.State,
            .fnUpdate = Update,
        };
    }
};

//------------------------------------------------------------------------------
// GDraw

// TODO: move custom text helpers from here to libannodue
const rt = @import("racer").Text;

/// convenience function for drawing text with default style, default color, on
/// the default layer. common case for debug readouts.
pub fn GDrawTextDefault(gf: *PluginAPI, x: i16, y: i16, comptime fmt: []const u8, args: anytype) bool {
    return gf.GDrawText(.Default, rt.hMakeText(x, y, fmt, args, null, null) catch return false);
}
