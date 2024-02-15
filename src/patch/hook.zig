pub const Self = @This();

const std = @import("std");
const win = std.os.windows;

const mem = @import("util/memory.zig");

const ALIGN_SIZE: usize = 16;

pub fn addr_from_call(src_call: usize) usize {
    const orig_dest_rel: i32 = mem.read(src_call + 1, i32);
    const orig_dest_abs: usize = @bitCast(@as(i32, @bitCast(src_call + 5)) + orig_dest_rel);
    return orig_dest_abs;
}

pub fn detour(memory: usize, addr: usize, len: usize, dest_before: ?*const fn () void, dest_after: ?*const fn () void) usize {
    std.debug.assert(len >= 5);

    const scr_alloc = win.MEM_COMMIT | win.MEM_RESERVE;
    const scr_protect = win.PAGE_EXECUTE_READWRITE;
    const scratch = win.VirtualAlloc(null, len, scr_alloc, scr_protect) catch unreachable;
    defer win.VirtualFree(scratch, 0, win.MEM_RELEASE);
    mem.read_bytes(addr, scratch, len);

    var off: usize = memory;

    const off_hook: usize = mem.call(addr, off);
    _ = mem.nop_until(off_hook, addr + len);

    if (dest_before) |dest| off = mem.call(off, @intFromPtr(dest));
    off = mem.write_bytes(off, scratch, len);
    if (dest_after) |dest| off = mem.call(off, @intFromPtr(dest));
    off = mem.retn(off);
    off = mem.nop_align(off, ALIGN_SIZE);

    return off;
}

pub fn intercept_call(memory: usize, off_call: usize, dest_before: ?*const fn () void, dest_after: ?*const fn () void) usize {
    const call_target: usize = addr_from_call(off_call);

    var off: usize = memory;

    _ = mem.call(off_call, off);

    if (dest_before) |dest| off = mem.call(off, @intFromPtr(dest));
    off = mem.call(off, call_target);
    if (dest_after) |dest| off = mem.call(off, @intFromPtr(dest));
    off = mem.retn(off);
    off = mem.nop_align(off, ALIGN_SIZE);

    return off;
}

pub fn intercept_jumptable(memory: usize, jt_addr: usize, jt_idx: u32, dest: *const fn () void) usize {
    const item_addr: usize = jt_addr + 4 * jt_idx;
    const item_target: usize = mem.read(item_addr, u32);
    var off: usize = memory;

    _ = mem.write(item_addr, u32, off);

    off = mem.call(off, @intFromPtr(dest));
    off = mem.jmp(off, item_target);
    off = mem.nop_align(off, ALIGN_SIZE);

    return off;
}
