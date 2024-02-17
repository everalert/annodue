pub const Self = @This();

const std = @import("std");
const win = std.os.windows;

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
    var protect: win.DWORD = undefined;
    _ = win.VirtualProtect(addr, @sizeOf(T), win.PAGE_EXECUTE_READWRITE, &protect) catch unreachable;
    @memcpy(addr, &data);
    _ = win.VirtualProtect(addr, @sizeOf(T), protect, &protect) catch unreachable;
    return offset + @sizeOf(T);
}

pub fn write_bytes(offset: usize, ptr_in: ?*anyopaque, len: usize) usize {
    const addr: [*]align(1) u8 = @ptrFromInt(offset);
    const data: []u8 = @as([*]u8, @ptrCast(ptr_in))[0..len];
    var protect: win.DWORD = undefined;
    _ = win.VirtualProtect(addr, len, win.PAGE_EXECUTE_READWRITE, &protect) catch unreachable;
    @memcpy(addr, data);
    _ = win.VirtualProtect(addr, len, protect, &protect) catch unreachable;
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
