pub const Self = @This();

const std = @import("std");

const mem = @import("memory.zig");
const x86 = @import("x86.zig");

pub const ALIGN_SIZE: usize = 16;
pub const DETOUR_LIMIT: usize = 32;

pub fn addr_from_call(src_call: usize) usize {
    const orig_dest_rel: i32 = mem.read(src_call + 1, i32);
    const orig_dest_abs: usize = @bitCast(@as(i32, @bitCast(src_call + 5)) + orig_dest_rel);
    return orig_dest_abs;
}

// FIXME: the naming of these functions sucks balls
// also, the naming of the arguments

// TODO: version that only detours a CALL (5 bytes) with JMP, for simplicity
// NOTE: assumes no relative shenanigans are in the detoured range other than
// the intercepted CALL
/// @addr_detour    the starting address of the sequence of instructions to replace
/// @off_call       the number of bytes after @addr_detour where the CALL instruction to replace is
/// @len            the total length of the sequence of instructions to replace
pub fn detour_call(memory: usize, addr_detour: usize, off_call: usize, len: usize, dest_before: ?*const fn () void, dest_after: ?*const fn () void) usize {
    std.debug.assert(len >= 5);
    std.debug.assert(len <= DETOUR_LIMIT);
    std.debug.assert(off_call <= len - 5);

    var off: usize = memory;

    const call_target: usize = addr_from_call(addr_detour + off_call);
    var scratch: [DETOUR_LIMIT]u8 = undefined;
    mem.read_bytes(addr_detour, &scratch, len);

    const off_hook: usize = x86.jmp(addr_detour, off);
    _ = x86.nop_until(off_hook, addr_detour + len);

    if (dest_before) |dest| off = x86.call(off, @intFromPtr(dest));
    off = mem.write_bytes(off, &scratch[0], off_call);
    off = x86.call(off, call_target);
    off = mem.write_bytes(off, &scratch[off_call + 5], len - off_call - 5);
    if (dest_after) |dest| off = x86.call(off, @intFromPtr(dest));
    off = x86.jmp(off, addr_detour + len);
    off = x86.nop_align(off, ALIGN_SIZE);

    return off;
}

// detour without hooking a function
pub fn detour(memory: usize, addr: usize, len: usize, dest_before: ?*const fn () void, dest_after: ?*const fn () void) usize {
    std.debug.assert(len >= 5);
    std.debug.assert(len <= DETOUR_LIMIT);

    var scratch: [DETOUR_LIMIT]u8 = undefined;
    mem.read_bytes(addr, &scratch, len);

    var off: usize = memory;

    const off_hook: usize = x86.call(addr, off);
    _ = x86.nop_until(off_hook, addr + len);

    if (dest_before) |dest| off = x86.jmp(off, @intFromPtr(dest));
    off = mem.write_bytes(off, &scratch, len);
    if (dest_after) |dest| off = x86.jmp(off, @intFromPtr(dest));
    off = x86.retn(off);
    off = x86.nop_align(off, ALIGN_SIZE);

    return off;
}

/// @addr    address of the original RETN instruction; requires 4 trailing NOPs
pub fn detour_retn(memory: usize, addr: usize, dest: *const fn () void) usize {
    std.debug.assert(std.mem.eql(u8, @as(*[5]u8, @ptrFromInt(addr)), &[5]u8{ 0xC3, 0x90, 0x90, 0x90, 0x90 }));

    var off: usize = memory;

    _ = x86.jmp(addr, off);

    off = x86.call(off, @intFromPtr(dest));
    off = x86.retn(off);
    off = x86.nop_align(off, ALIGN_SIZE);

    return off;
}

pub fn intercept_call(memory: usize, off_call: usize, dest_before: ?*const fn () void, dest_after: ?*const fn () void) usize {
    const call_target: usize = addr_from_call(off_call);

    var off: usize = memory;

    _ = x86.call(off_call, off);

    if (dest_before) |dest| off = x86.call(off, @intFromPtr(dest));
    off = x86.call(off, call_target);
    if (dest_after) |dest| off = x86.call(off, @intFromPtr(dest));
    off = x86.retn(off);
    off = x86.nop_align(off, ALIGN_SIZE);

    return off;
}

pub fn intercept_jumptable(memory: usize, jt_addr: usize, jt_idx: u32, dest: *const fn () void) usize {
    const item_addr: usize = jt_addr + 4 * jt_idx;
    const item_target: usize = mem.read(item_addr, u32);
    var off: usize = memory;

    _ = mem.write(item_addr, u32, off);

    off = x86.call(off, @intFromPtr(dest));
    off = x86.jmp(off, item_target);
    off = x86.nop_align(off, ALIGN_SIZE);

    return off;
}
