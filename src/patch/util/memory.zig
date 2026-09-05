//! patching-friedly memory read/write api
//!
//! defs:
//!   "safe"    correct page permissions are ensured via OS api
//!   "unsafe"  correct page permissions are assumed; use to avoid spamming
//!             OS api calls when you know the permissions are good
//!
//! usage:
//! - tagged `Safe` functions are "safe" as defined above
//! - tagged `Deref` functions resolve an address at the end of a pointer chain
//!   before doing the action. these functions are "unsafe"; there are no "safe"
//!   versions for the sake of simplicity
//! - untagged functions are "unsafe". use `SafeContext` functions to use these
//!   functions safely in bulk
//! - `Write` functions return the address at the end of the written range (one
//!   byte after the last written byte); this is so you can do iterative writes
//!   without manually keeping track of the next address at each step

// TODO: tests; see core_address for inspo
// TODO: update core_address to use this, now that it's straightened out?
// TODO: extract VirtualProtect bit to a util/os thing (OS_Memory_SetProtection or smth)
// TODO: look into perf cost of spamming VirtualProtect

const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;

const w32 = @import("zigwin32");
const PAGE_PROTECTION_FLAGS = w32.system.memory.PAGE_PROTECTION_FLAGS;
const PAGE_EXECUTE_READWRITE = w32.system.memory.PAGE_EXECUTE_READWRITE;
const FALSE = w32.zig.FALSE;
const VirtualProtect = w32.system.memory.VirtualProtect;
const GetLastError = w32.foundation.GetLastError;

//------------------------------------------------------------------------------
// "unsafe" api

/// write value to address, assuming correct page permissions
pub fn Write(addr: usize, comptime T: type, value: T) usize {
    if (@bitSizeOf(T) == 0) return addr;
    const a: [*]align(1) u8 = @ptrFromInt(addr);
    const data: []const u8 = @as([*]const u8, @ptrCast(&value))[0..@sizeOf(T)];
    @memcpy(a, data);
    return addr + @sizeOf(T);
}

/// write bytes to address, assuming correct page permissions
pub fn WriteBytes(addr: usize, data: []const u8) usize {
    if (data.len == 0) return addr;
    const a: [*]align(1) u8 = @ptrFromInt(addr);
    @memcpy(a, data);
    return addr + data.len;
}

// TODO: check if placing the value on the stack first is necessary
// TODO: check if setting align(1) is necessary
/// read value from address, assuming correct page permissions
pub fn Read(addr: usize, comptime T: type) T {
    const a: [*]align(1) T = @ptrFromInt(addr);
    var data: [1]T = undefined;
    @memcpy(&data, a);
    return data[0];
}

/// read bytes from address, assuming correct page permissions
pub fn ReadBytes(addr: usize, data: []u8) void {
    const a: [*]u8 = @ptrFromInt(addr);
    @memcpy(data, a);
}

//------------------------------------------------------------------------------
// pointer chain api

/// resolve address at end of pointer chain
pub fn Deref(addr: usize, path: []const usize) usize {
    var a: usize = addr;
    for (path[0 .. path.len - 1]) |p| a = Read(a + p);
    return a + path[path.len - 1];
}

/// write value at end of pointer chain, assuming correct page permissions along the chain
pub fn DerefWrite(addr: usize, path: []const usize, comptime T: type, value: T) usize {
    const a = Deref(addr, path);
    return Write(a, T, value);
}

/// write bytes at end of pointer chain, assuming correct page permissions along the chain
pub fn DerefWriteBytes(addr: usize, path: []const usize, data: []const u8) usize {
    const a = Deref(addr, path);
    return Write(a, data);
}

/// read value at end of pointer chain, assuming correct page permissions along the chain
pub fn DerefRead(addr: usize, path: []const usize, comptime T: type) T {
    const a = Deref(addr, path);
    return Read(a, T);
}

/// read bytes at end of pointer chain, assuming correct page permissions along the chain
pub fn DerefReadBytes(addr: usize, path: []const usize, data: []u8) void {
    const a = Deref(addr, path);
    Read(a, data);
}

//------------------------------------------------------------------------------
// "safe" api

// write value to address, using OS api to ensure correct page permissions
pub fn SafeWrite(addr: usize, comptime T: type, value: T) usize {
    const ctx = SafeContextSt(addr, addr + @sizeOf(T));
    defer SafeContextEd(ctx);
    return Write(addr, T, value);
}

// write bytes to address, using OS api to ensure correct page permissions
pub fn SafeWriteBytes(addr: usize, data: []const u8) usize {
    const ctx = SafeContextSt(addr, addr + data.len);
    defer SafeContextEd(ctx);
    return WriteBytes(addr, data);
}

// read value from address, using OS api to ensure correct page permissions
pub fn SafeRead(addr: usize, comptime T: type) T {
    const ctx = SafeContextSt(addr, addr + @sizeOf(T));
    defer SafeContextEd(ctx);
    return Read(addr, T);
}

// read bytes from address, using OS api to ensure correct page permissions
pub fn SafeReadBytes(addr: usize, data: []u8) void {
    const ctx = SafeContextSt(addr, addr + data.len);
    defer SafeContextEd(ctx);
    ReadBytes(addr, data);
}

//------------------------------------------------------------------------------
// safety context helper

const Context = struct {
    Addr: ?*anyopaque,
    Size: usize,
    Flags: PAGE_PROTECTION_FLAGS,
};

/// make an address range safe to read/write to, using OS api to set page permissions,
/// allowing safe bulk use of "unsafe" api with a single permissions cycle. user must
/// use `SafeContextEd` to restore previous permissions when done.
pub fn SafeContextSt(addr_st: usize, addr_ed: usize) Context {
    assert(addr_st > 0);
    assert(addr_ed > addr_st);
    var ctx: Context = .{ .Addr = @ptrFromInt(addr_st), .Size = addr_ed - addr_st, .Flags = undefined };
    if (FALSE == VirtualProtect(ctx.Addr, ctx.Size, PAGE_EXECUTE_READWRITE, &ctx.Flags))
        panic("SafeContextSt: VirtualProtect: {s}", .{@tagName(GetLastError())});
    return ctx;
}

pub fn SafeContextEd(ctx: Context) void {
    var flags: PAGE_PROTECTION_FLAGS = undefined; // needed for valid api usage
    if (FALSE == VirtualProtect(ctx.Addr, ctx.Size, ctx.Flags, &flags))
        panic("SafeContextEd: VirtualProtect: {s}", .{@tagName(GetLastError())});
}
