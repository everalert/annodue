const GlobalFn = @import("../../core/SharedDef.zig").GlobalFunction;

pub inline fn AMemoryGetPermanentT(gf: *GlobalFn, comptime T: type) ?*T {
    return @as(*T, @ptrCast(gf.AMemoryGetPermanent(@sizeOf(T)) orelse return null));
}

pub inline fn AMemoryGetPermanentZeroT(gf: *GlobalFn, comptime T: type) ?*T {
    return @as(*T, @ptrCast(gf.AMemoryGetPermanentZero(@sizeOf(T)) orelse return null));
}

pub inline fn AMemoryGetTemporaryT(gf: *GlobalFn, comptime T: type) ?*T {
    return @as(*T, @ptrCast(gf.AMemoryGetTemporary(@sizeOf(T)) orelse return null));
}

pub inline fn AMemoryGetTemporaryZeroT(gf: *GlobalFn, comptime T: type) ?*T {
    return @as(*T, @ptrCast(gf.AMemoryGetTemporaryZero(@sizeOf(T)) orelse return null));
}
