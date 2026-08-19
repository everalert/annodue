//! bump allocator with growable contiguous memory
//!
//! - max capacity is defined upfront
//! - only commits real memory when needed
//! - memory guaranteed to be stable and contiguous (no realloc)
//! - memory chunks returned are aligned to architecture pointer size
//! - can fully or partially reset without violating stability or contiguity guarantees
const Arena = @This();

// TODO: platform-agnostic implementation
// TODO: debug ft such as asan poisoning unused committed range after SizeUsed changes
// TODO: confirm tests via running package tests from build script (zigwin32 not
//  conveniently available when testing standalone)
// TODO: maybe align addresses when pushing, not in advance. this way there could
//  be an option for the user to specify the alignment they want, and it would
//  play more nicely with std allocator impl

const std = @import("std");
const builtin = @import("builtin");
const StdAllocator = std.mem.Allocator;
const assert = std.debug.assert;

const POINTER_ALIGNMENT = builtin.target.maxIntAlignment();

const RoundIntUp = @import("base_math.zig").RoundIntUp;
const KiB = @import("base_memory.zig").KiB;
const MiB = @import("base_memory.zig").MiB;

const w32 = @import("zigwin32");
const SYSTEM_INFO = w32.system.system_information.SYSTEM_INFO;
const MEM_COMMIT = w32.system.memory.VIRTUAL_ALLOCATION_TYPE{ .COMMIT = 1 };
const MEM_RESERVE = w32.system.memory.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1 };
const MEM_RELEASE = w32.system.memory.VIRTUAL_FREE_TYPE.RELEASE;
const MEM_DECOMMIT = w32.system.memory.VIRTUAL_FREE_TYPE.DECOMMIT;
const PAGE_NOACCESS = w32.system.memory.PAGE_PROTECTION_FLAGS{ .PAGE_NOACCESS = 1 };
const PAGE_READWRITE = w32.system.memory.PAGE_PROTECTION_FLAGS{ .PAGE_READWRITE = 1 };
const VirtualAlloc = w32.system.memory.VirtualAlloc;
const VirtualFree = w32.system.memory.VirtualFree;
const GetSystemInfo = w32.system.system_information.GetSystemInfo;

pMemory: ?*anyopaque,
SizeReserved: usize,
SizeCommitted: usize,
SizeUsed: usize,
SizeUsedMax: usize,
CommitIncrement: usize,

/// init arena and reserve memory range in the os
/// @size               number of bytes to reserve, rounded up to allocation granularity
/// @commit_increment   number of bytes to commit at a time, rounded up to page size
/// @return             non-null if reserving memory is successful
pub fn Init(size: usize, commit_increment: usize) ?Arena {
    comptime if (builtin.target.os.tag != .windows) @compileError("implementation is windows-only");

    var system_info: SYSTEM_INFO = undefined;
    GetSystemInfo(&system_info);

    const size_res = RoundIntUp(usize, size, system_info.dwAllocationGranularity);
    const size_inc = RoundIntUp(usize, commit_increment, system_info.dwPageSize);

    var alloc = VirtualAlloc(null, size_res, MEM_RESERVE, PAGE_NOACCESS) orelse return null;

    return Arena{
        .pMemory = alloc,
        .SizeReserved = size_res,
        .SizeCommitted = 0,
        .SizeUsed = 0,
        .SizeUsedMax = 0,
        .CommitIncrement = size_inc,
    };
}

/// releases reserved memory and invalidates arena
pub fn Deinit(self: *Arena) void {
    _ = VirtualFree(self.pMemory, 0, MEM_RELEASE);
    self.* = std.mem.zeroes(Arena);
}

/// get a byte range aligned to platform pointer size, or return null if out of memory
pub fn Push(self: *Arena, size: usize) []u8 {
    assert(self.SizeUsed % POINTER_ALIGNMENT == 0);

    const size_alloc = RoundIntUp(usize, size, POINTER_ALIGNMENT);
    const size_used_next = self.SizeUsed + size_alloc;

    if (size_used_next > self.SizeReserved) return &.{};

    if (size_used_next > self.SizeCommitted) {
        const size_committed_next = RoundIntUp(usize, size_used_next, self.CommitIncrement);
        _ = VirtualAlloc(self.pMemory, size_committed_next, MEM_COMMIT, PAGE_READWRITE) orelse return &.{};
        self.SizeCommitted = size_committed_next;
    }

    const pointer = @intFromPtr(self.pMemory.?) + self.SizeUsed;
    self.SizeUsed += size_alloc;
    self.SizeUsedMax = @max(self.SizeUsedMax, self.SizeUsed);

    return @as([*]u8, @ptrFromInt(pointer))[0..size];
}

/// get a zero-ed byte range
pub fn PushZero(self: *Arena, size: usize) []u8 {
    const mem = self.Push(size);
    @memset(mem, 0);
    return mem;
}

/// pop all pushed bytes
pub fn Pop(self: *Arena) void {
    self.PopTo(0);
}

/// pop bytes, leaving at least @size bytes pushed
pub fn PopTo(self: *Arena, size: usize) void {
    assert(size <= self.SizeUsed);
    defer assert(self.SizeUsed % POINTER_ALIGNMENT == 0);
    self.SizeUsed = RoundIntUp(usize, size, POINTER_ALIGNMENT);
}

/// decommit all committed memory, and pop all pushed memory. does not release memory.
pub fn Reset(self: *Arena) void {
    self.ResetTo(0);
}

/// decommit committed memory, leaving at least @size bytes committed, and leaving
/// at least @size bytes pushed. does not release memory.
pub fn ResetTo(self: *Arena, size: usize) void {
    assert(self.pMemory != null);
    assert(size <= self.SizeCommitted);
    defer assert(self.SizeUsed <= self.SizeCommitted);

    const size_committed_next = RoundIntUp(usize, size, self.CommitIncrement);
    const size_decommit = self.SizeReserved - size_committed_next;
    const pointer = @intFromPtr(self.pMemory.?) + size_committed_next;

    _ = VirtualFree(@ptrFromInt(pointer), size_decommit, MEM_DECOMMIT);
    self.SizeCommitted = size_committed_next;
    self.PopTo(size);
}

pub fn Allocator(self: *Arena) StdAllocator {
    return StdAllocator{
        .ptr = self,
        .vtable = &StdAllocator.VTable{
            .alloc = AllocatorAlloc,
            .resize = AllocatorResize,
            .free = AllocatorFree,
        },
    };
}

// TODO: support log2_ptr_align
fn AllocatorAlloc(ctx: *anyopaque, n: usize, _: u8, _: usize) ?[*]u8 {
    const self: *Arena = @ptrCast(@alignCast(ctx));
    var mem = self.Push(n);
    return if (mem.len == n) mem.ptr else null;
}

// TODO: support full range of resize actions. missing: expanding if last alloc,
//  maybe shrinking if non-last (unsure atm and neither relevant to my usage)
fn AllocatorResize(ctx: *anyopaque, buf: []u8, _: u8, new_len: usize, _: usize) bool {
    const self: *Arena = @ptrCast(@alignCast(ctx));

    const buf_len_aligned = RoundIntUp(usize, buf.len, POINTER_ALIGNMENT);
    const buf_end = @intFromPtr(buf.ptr) + buf_len_aligned;
    const b_last_alloc = if (self.pMemory) |mem| buf_end == @intFromPtr(mem) + self.SizeUsed else false;

    if (!b_last_alloc or new_len > buf.len) return false;

    self.PopTo(self.SizeUsed - buf_len_aligned + new_len);
    return true;
}

fn AllocatorFree(ctx: *anyopaque, buf: []u8, _: u8, _: usize) void {
    const self: *Arena = @ptrCast(@alignCast(ctx));

    const buf_len_aligned = RoundIntUp(usize, buf.len, POINTER_ALIGNMENT);
    const buf_end = @intFromPtr(buf.ptr) + buf_len_aligned;
    const b_last_alloc = if (self.pMemory) |mem| buf_end == @intFromPtr(mem) + self.SizeUsed else false;

    if (b_last_alloc) self.PopTo(self.SizeUsed - buf_len_aligned);
}

// TODO: tests for page size
// TODO: tests for allocation granularity
// TODO: tests for std allocator impl
test {
    const size_res = MiB(usize, 10);
    const size_inc = MiB(usize, 1);
    const size_mem1 = KiB(usize, 1);
    const size_mem2 = size_inc;
    const size_mem3 = size_res;

    var arena = Arena.Init(size_res, size_inc) orelse return error.OutOfMemory;
    try std.testing.expect(arena.pMemory != null);
    try std.testing.expect(arena.SizeReserved == size_res);
    try std.testing.expect(arena.SizeCommitted == 0);

    // getting memory
    var mem1 = arena.Push(size_mem1);
    try std.testing.expect(mem1.len == size_mem1);
    try std.testing.expect(arena.SizeUsed == size_mem1);
    try std.testing.expect(arena.SizeCommitted == size_inc);

    // getting zero-ed memory
    var mem2 = arena.PushZero(size_mem2);
    try std.testing.expect(mem2.len == size_mem2);
    try std.testing.expect(std.mem.count(mem2, &.{0}) == size_mem2);
    try std.testing.expect(arena.SizeUsed == size_mem1 + size_mem2);
    try std.testing.expect(arena.SizeCommitted == size_inc * 2);

    // over-running reserve size
    var mem3 = arena.Push(size_mem3);
    try std.testing.expect(mem3.len == 0);
    try std.testing.expect(arena.SizeUsed == size_mem1 + size_mem2); // unchanged
    try std.testing.expect(arena.SizeCommitted == size_inc * 2); // unchanged

    // decommitting memory
    arena.ResetTo(size_mem1);
    try std.testing.expect(arena.SizeUsed == size_mem1);
    try std.testing.expect(arena.SizeCommitted == size_inc);
    try std.testing.expect(arena.SizeUsedMax == size_mem1 + size_mem2);

    // "freeing" memory
    arena.Pop();
    try std.testing.expect(arena.SizeUsed == 0);
    try std.testing.expect(arena.SizeCommitted == size_inc); // unchanged
    try std.testing.expect(arena.SizeUsedMax == size_mem1 + size_mem2); // unchanged

    // releasing memory
    arena.Deinit();
    try std.testing.expect(arena.pMemory == null);
    try std.testing.expect(arena.SizeUsed == 0);
    try std.testing.expect(arena.SizeCommitted == 0);
    try std.testing.expect(arena.SizeReserved == 0);
}
