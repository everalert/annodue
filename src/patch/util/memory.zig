pub const Self = @This();

const std = @import("std");

const VirtualProtect = std.os.windows.VirtualProtect;
const VirtualAlloc = std.os.windows.VirtualAlloc;
const VirtualFree = std.os.windows.VirtualFree;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const MEM_RELEASE = std.os.windows.MEM_RELEASE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;
const DWORD = std.os.windows.DWORD;

const ALIGN_SIZE: usize = 16;

// TODO: experiment with unprotected/raw memory access without the bullshit
// - switching to PAGE_EXECUTE_READWRITE is required
// - maybe add fns: write_unsafe, write_unsafe_enable, write_unsafe_disable ?
//     then you could do something like:
//     GameLoopAfter() {
//        write_unsafe_enable();
//        function_containing_write_unsafe();
//        ...
//        write_unsafe_disable();
//     }
//     and only have to set it a handful of times outside of special cases
// - need to know exactly the perf cost of calling virtualprotect to know
//     if making a arch shift is worth it tho

// NOTE: mod r/m table here
// https://www.cs.uaf.edu/2016/fall/cs301/lecture/09_28_machinecode.html

pub fn write(offset: usize, comptime T: type, value: T) usize {
    const addr: [*]align(1) T = @ptrFromInt(offset);
    const data: [1]T = [1]T{value};
    var protect: DWORD = undefined;
    _ = VirtualProtect(addr, @sizeOf(T), PAGE_EXECUTE_READWRITE, &protect) catch unreachable;
    @memcpy(addr, &data);
    _ = VirtualProtect(addr, @sizeOf(T), protect, &protect) catch unreachable;
    return offset + @sizeOf(T);
}

pub fn write_bytes(offset: usize, ptr_in: ?*anyopaque, len: usize) usize {
    const addr: [*]u8 = @ptrFromInt(offset);
    const data: []u8 = @as([*]u8, @ptrCast(ptr_in))[0..len];
    var protect: DWORD = undefined;
    _ = VirtualProtect(addr, len, PAGE_EXECUTE_READWRITE, &protect) catch unreachable;
    @memcpy(addr, data);
    _ = VirtualProtect(addr, len, protect, &protect) catch unreachable;
    return offset + len;
}

pub fn read(offset: usize, comptime T: type) T {
    const addr: [*]align(1) T = @ptrFromInt(offset);
    var data: [1]T = undefined;
    @memcpy(&data, addr);
    return data[0];
}

pub fn read_bytes(offset: usize, ptr_out: ?*anyopaque, len: usize) void {
    const addr: [*]u8 = @ptrFromInt(offset);
    const data: []u8 = @as([*]u8, @ptrCast(ptr_out))[0..len];
    @memcpy(data, addr);
}

pub fn patch_add(offset: usize, comptime T: type, delta: T) usize {
    const value: T = read(offset, T);
    return write(offset, T, value + delta);
}

pub fn add_rm32_imm8(memory_offset: usize, rm32: u8, imm8: u8) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x83);
    offset = write(offset, u8, rm32);
    offset = write(offset, u8, imm8);
    return offset;
}

pub fn add_esp8(memory_offset: usize, value: u8) usize {
    return add_rm32_imm8(memory_offset, 0xC4, value);
}

pub fn add_rm32_imm32(memory_offset: usize, rm32: u8, imm32: u32) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x81);
    offset = write(offset, u8, rm32);
    offset = write(offset, u32, imm32);
    return offset;
}

pub fn add_esp32(memory_offset: usize, value: u32) usize {
    return add_rm32_imm32(memory_offset, 0xC4, value);
}

pub fn test_rm32_r32(memory_offset: usize, r32: u8) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x85);
    offset = write(offset, u8, r32);
    return offset;
}

pub fn test_eax_eax(memory_offset: usize) usize {
    return test_rm32_r32(memory_offset, 0xC0);
}

pub fn test_edx_edx(memory_offset: usize) usize {
    return test_rm32_r32(memory_offset, 0xD2);
}

pub fn mov_r32_rm32(memory_offset: usize, r32: u8, comptime T: type, rm32: T) usize {
    std.debug.assert(T == u8 or T == u32);
    var offset = memory_offset;
    offset = write(offset, u8, 0x8B);
    offset = write(offset, u8, r32);
    offset = write(offset, T, rm32);
    return offset;
}

pub fn mov_ecx_b(memory: usize, b: u8) usize {
    return mov_r32_rm32(memory, 0x4E, u8, b);
}

pub fn mov_edx(memory_offset: usize, value: u32) usize {
    return mov_r32_rm32(memory_offset, 0x15, u32, value);
}

pub fn mov_rm32_r32(memory_offset: usize, r32: u8) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x89);
    offset = write(offset, u8, r32);
    return offset;
}

pub fn mov_edx_esp(memory_offset: usize) usize {
    return mov_rm32_r32(memory_offset, 0xE2);
}

pub fn nop(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x90);
}

pub fn nop_align(memory_offset: usize, increment: usize) usize {
    var offset: usize = memory_offset;
    while (offset % increment > 0) {
        offset = nop(offset);
    }
    return offset;
}

pub fn nop_until(memory_offset: usize, end: usize) usize {
    var offset: usize = memory_offset;
    while (offset < end) {
        offset = nop(offset);
    }
    return offset;
}

pub fn push_eax(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x50);
}

pub fn push_edx(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x52);
}

pub fn push_ebp(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x55);
}

pub fn push_esi(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x56);
}

pub fn push_edi(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x57);
}

pub fn pop_eax(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x58);
}

pub fn pop_edx(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x5A);
}

pub fn pop_edi(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x5F);
}

pub fn pop_esi(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x5E);
}

pub fn pop_ebp(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x5D);
}

pub fn pop_ebx(memory_offset: usize) usize {
    return write(memory_offset, u8, 0x5B);
}

pub fn push_u32(memory_offset: usize, value: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x68);
    offset = write(offset, u32, value);
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
// call_rel32
pub fn call(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0xE8);
    offset = write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}
pub fn call_rm32(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0xFF);
    offset = write(offset, u32, address);
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
// jmp_rel32
pub fn jmp(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0xE9);
    offset = write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
// jcc jnz_rel32
pub fn jnz(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x0F);
    offset = write(offset, u8, 0x85);
    offset = write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}

pub fn jz_rel8(memory: usize, value: i8) usize {
    var offset = memory;
    offset = write(offset, u8, 0x74);
    offset = write(offset, i8, value);
    return offset;
}

// WARN: could underflow, but not likely for our use case i guess
// jcc jz_rel32
pub fn jz(memory_offset: usize, address: usize) usize {
    var offset = memory_offset;
    offset = write(offset, u8, 0x0F);
    offset = write(offset, u8, 0x84);
    offset = write(offset, i32, @as(i32, @bitCast(address)) - (@as(i32, @bitCast(offset)) + 4));
    //offset = write(offset, u32, address - (offset + 4));
    return offset;
}

pub fn retn(memory_offset: usize) usize {
    return write(memory_offset, u8, 0xC3);
}

pub fn addr_from_call(src_call: usize) usize {
    const orig_dest_rel: i32 = read(src_call + 1, i32);
    const orig_dest_abs: usize = @bitCast(@as(i32, @bitCast(src_call + 5)) + orig_dest_rel);
    return orig_dest_abs;
}

pub fn detour(memory: usize, addr: usize, len: usize, dest_before: ?*const fn () void, dest_after: ?*const fn () void) usize {
    std.debug.assert(len >= 5);

    const scr_alloc = MEM_COMMIT | MEM_RESERVE;
    const scr_protect = PAGE_EXECUTE_READWRITE;
    const scratch = VirtualAlloc(null, len, scr_alloc, scr_protect) catch unreachable;
    defer VirtualFree(scratch, 0, MEM_RELEASE);
    read_bytes(addr, scratch, len);

    var off: usize = memory;

    const off_hook: usize = call(addr, off);
    _ = nop_until(off_hook, addr + len);

    if (dest_before) |dest| off = call(off, @intFromPtr(dest));
    off = write_bytes(off, scratch, len);
    if (dest_after) |dest| off = call(off, @intFromPtr(dest));
    off = retn(off);
    off = nop_align(off, ALIGN_SIZE);

    return off;
}

pub fn intercept_call(memory: usize, off_call: usize, dest_before: ?*const fn () void, dest_after: ?*const fn () void) usize {
    const call_target: usize = addr_from_call(off_call);

    var off: usize = memory;

    _ = call(off_call, off);

    if (dest_before) |dest| off = call(off, @intFromPtr(dest));
    off = call(off, call_target);
    if (dest_after) |dest| off = call(off, @intFromPtr(dest));
    off = retn(off);
    off = nop_align(off, ALIGN_SIZE);

    return off;
}

pub fn intercept_jump_table(memory: usize, jt_addr: usize, jt_idx: u32, dest: *const fn () void) usize {
    const item_addr: usize = jt_addr + 4 * jt_idx;
    const item_target: usize = read(item_addr, u32);
    var off: usize = memory;

    _ = write(item_addr, u32, off);

    off = call(off, @intFromPtr(dest));
    off = jmp(off, item_target);
    off = nop_align(off, ALIGN_SIZE);

    return off;
}

// FIXME: error handling/path validation
pub fn deref(path: []const usize) usize {
    var i: u32 = 0;
    var addr: usize = 0;
    while (i < path.len - 1) : (i += 1) {
        addr = read(addr + path[i], u32);
    }
    return addr + path[i];
}

pub fn deref_read(path: []const usize, comptime T: type) T {
    const addr = deref(path);
    return read(addr, T);
}
