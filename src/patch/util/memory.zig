pub const Self = @This();

const std = @import("std");
const panic = std.debug.panic;

const w32 = @import("zigwin32");
const PAGE_PROTECTION_FLAGS = w32.system.memory.PAGE_PROTECTION_FLAGS;
const PAGE_EXECUTE_READWRITE = w32.system.memory.PAGE_EXECUTE_READWRITE;
const FALSE = w32.zig.FALSE;
const VirtualProtect = w32.system.memory.VirtualProtect;
const GetLastError = w32.foundation.GetLastError;

// TODO: write page protection for reading functions too? for api symmetry

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

// FIXME: rework write* stuff to be named better (unsafe/unprotected is weirdge)
// FIXME: change x86 api to use unsafe versions (i.e. make it more convenient
//  for users to use RAddress api/easier to find bad usage)
// FIXME: extract VirtualProtect bit to a util/os thing (OS_Memory_SetProtection or smth)
// FIXME: technically a memory range might not have read rights? so read_* should
//  also set VirtualProtect and have "unsafe" versions?

pub fn write(offset: usize, comptime T: type, value: T) usize {
    if (@bitSizeOf(T) == 0) return offset;
    const addr: [*]align(1) u8 = @ptrFromInt(offset);
    const data: []const u8 = @as([*]const u8, @ptrCast(&value))[0..@sizeOf(T)];
    write_unprotected(addr, data);
    return offset + @sizeOf(T);
}

pub fn write_bytes(offset: usize, data: []const u8) usize {
    if (data.len == 0) return offset;
    const addr: [*]align(1) u8 = @ptrFromInt(offset);
    write_unprotected(addr, data);
    return offset + data.len;
}

fn write_unprotected(dst: [*]u8, src: []const u8) void {
    var protect: PAGE_PROTECTION_FLAGS = undefined;
    if (FALSE == VirtualProtect(dst, src.len, PAGE_EXECUTE_READWRITE, &protect))
        panic("write_unprotected: VirtualProtect(set): {s}", .{@tagName(GetLastError())});
    defer _ = if (FALSE == VirtualProtect(dst, src.len, protect, &protect))
        panic("write_unprotected: VirtualProtect(restore): {s}", .{@tagName(GetLastError())});
    @memcpy(dst, src);
}

pub fn write_unsafe(offset: usize, comptime T: type, value: T) usize {
    if (@bitSizeOf(T) == 0) return offset;
    const addr: [*]align(1) u8 = @ptrFromInt(offset);
    const data: []const u8 = @as([*]const u8, @ptrCast(&value))[0..@sizeOf(T)];
    write_assume_safe(addr, data);
    return offset + @sizeOf(T);
}

pub fn write_bytes_unsafe(offset: usize, data: []const u8) usize {
    if (data.len == 0) return offset;
    const addr: [*]align(1) u8 = @ptrFromInt(offset);
    write_assume_safe(addr, data);
    return offset + data.len;
}

/// write while assuming that the memory already has write permissions
fn write_assume_safe(dst: [*]u8, src: []const u8) void {
    @memcpy(dst, src);
}

pub fn read(offset: usize, comptime T: type) T {
    const addr: [*]align(1) T = @ptrFromInt(offset);
    var data: [1]T = undefined;
    @memcpy(&data, addr);
    return data[0];
}

pub fn read_bytes(offset: usize, data: []u8) void {
    const addr: [*]u8 = @ptrFromInt(offset);
    @memcpy(data, addr);
}

// TODO: remove?
pub fn patch_add(offset: usize, comptime T: type, delta: T) usize {
    const value: T = read(offset, T);
    return write(offset, T, value + delta);
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
