const std = @import("std");
const assert = std.debug.assert;

const api = @import("api.zig");

const GlobalFn = @import("../../core/SharedDef.zig").GlobalFunction;

//------------------------------------------------------------------------------
// AMemory

pub inline fn AMemoryGetPermanentT(gf: *GlobalFn, comptime T: type) ?*T {
    return @as(*T, @ptrCast(@alignCast(gf.AMemoryGetPermanent(@sizeOf(T)) orelse return null)));
}

pub inline fn AMemoryGetPermanentZeroT(gf: *GlobalFn, comptime T: type) ?*T {
    return @as(*T, @ptrCast(@alignCast(gf.AMemoryGetPermanentZero(@sizeOf(T)) orelse return null)));
}

pub inline fn AMemoryGetTemporaryT(gf: *GlobalFn, comptime T: type) ?*T {
    return @as(*T, @ptrCast(@alignCast(gf.AMemoryGetTemporary(@sizeOf(T)) orelse return null)));
}

pub inline fn AMemoryGetTemporaryZeroT(gf: *GlobalFn, comptime T: type) ?*T {
    return @as(*T, @ptrCast(@alignCast(gf.AMemoryGetTemporaryZero(@sizeOf(T)) orelse return null)));
}

//------------------------------------------------------------------------------
// RAddress

pub const RAddressHandle = api.RAddressHandle;
pub const RADDRESS_HANDLE_NULL = api.RADDRESS_HANDLE_NULL;

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

    pub fn Reserve(self: *RAddressHandleInfo, gf: *GlobalFn) void {
        self.Handle = gf.RAddressRangeReserve(self.AddrSt, self.AddrEd);
    }
};

/// returns `true` if range was reserved and its handle written to @handle_out
pub fn RAddressRangeReserveIfAvailable(gf: *GlobalFn, addr_st: u32, addr_ed: u32) RAddressHandle {
    const b_available = gf.RAddressRangeAvailable(addr_st, addr_ed);
    return if (b_available) gf.RAddressRangeReserve(addr_st, addr_ed) else RADDRESS_HANDLE_NULL;
}

pub fn RAddressRangeWrite(gf: *GlobalFn, handle: RAddressHandle, addr: u32, comptime T: type, val: T) bool {
    assert(gf.RAddressRangeContainsRange(handle, addr, addr + @sizeOf(T)));
    if (!gf.RAddressRangeWriteSt(handle)) return false;
    defer gf.RAddressRangeWriteEd(handle);

    const data: []const u8 = @as([*]const u8, @ptrCast(&val))[0..@sizeOf(T)];
    @memcpy(@as([*]u8, @ptrFromInt(addr)), data);
    return true;
}

pub fn RAddressRangeWriteBytes(gf: *GlobalFn, handle: RAddressHandle, addr: u32, buf: []const u8) bool {
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
pub fn RAddressPatchToggle(gf: *GlobalFn, handle: RAddressHandle, enable: bool) bool {
    if (handle == RADDRESS_HANDLE_NULL) return false;
    if (enable) return true;
    gf.RAddressRangeRestore(handle);
    return false;
}

/// same as `RAddressPatchToggle` but applies to a whole group collectively, performing
/// no action if any of the handles are invalid
pub fn RAddressPatchToggleGroup(gf: *GlobalFn, handles: []const RAddressHandle, enable: bool) bool {
    for (handles) |handle| if (handle == RADDRESS_HANDLE_NULL) return false;
    if (enable) return true;
    for (handles) |handle| gf.RAddressRangeRestore(handle);
    return false;
}

//------------------------------------------------------------------------------
// GDrawText

// TODO: move custom text helpers from here to libannodue
const rt = @import("racer").Text;

/// convenience function for drawing text with default style, default color, on
/// the default layer. common case for debug readouts.
pub fn GDrawTextDefault(gf: *GlobalFn, x: i16, y: i16, comptime fmt: []const u8, args: anytype) bool {
    return gf.GDrawText(.Default, rt.hMakeText(x, y, fmt, args, null, null) catch return false);
}
