const std = @import("std");

// FIXME: give unorganized stuff a home, and use this file exclusively for
//  forwarding modules/tests

//------------------------------------------------------------------------------
// unorganized stuff

const w32 = @import("zigwin32");
const GetModuleHandleExA = w32.system.library_loader.GetModuleHandleExA;
const FLAG_FROM_ADDRESS = w32.system.library_loader.GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS;
const FLAG_UNCHANGED_REFCOUNT = w32.system.library_loader.GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT;
const HINSTANCE = w32.foundation.HINSTANCE;
const FALSE = w32.zig.FALSE;

pub inline fn PCompileError(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [2048]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, fmt, args) catch @compileError(fmt);
    @compileError(out);
}

/// get base address of windows module executing this function. returns 0 if
/// unable to get address.
pub inline fn ModuleBaseAddress() usize {
    return ModuleBaseAddressFrom(@intFromPtr(&ModuleBaseAddressFrom));
}

/// get base address of windows module to which @src_address belongs. returns 0 if
/// unable to get address.
///  - to get the address of the currently-executing module, use `ModuleBaseAddress`
///  - to get the address of an undefined calling module (e.g. a parent DLL in a DLL
///    loading chain), pass @returnAddress into this function from an export function.
pub fn ModuleBaseAddressFrom(src_address: usize) usize {
    var hmod: ?HINSTANCE = null;
    const flags = FLAG_FROM_ADDRESS | FLAG_UNCHANGED_REFCOUNT;
    _ = GetModuleHandleExA(flags, @ptrFromInt(src_address), &hmod);
    return if (hmod) |h| @intFromPtr(h) else 0;
}
