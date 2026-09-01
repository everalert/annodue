const std = @import("std");
const assert = std.debug.assert;

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

// TODO: migrate api defs to libannodue and import this def instead of redefining it here
pub const RAddressHandle = u32;
pub const RADDRESS_HANDLE_NULL = 0;

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
