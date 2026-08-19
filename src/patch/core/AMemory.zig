const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const app = @import("../appinfo.zig");
const GlobalFn = app.GLOBAL_FUNCTION;

const BaseArena = @import("../util/base/base_arena.zig");
const MiB = @import("../util/base/base_memory.zig").MiB;
const KiB = @import("../util/base/base_memory.zig").KiB;

const SIZE_PERMANENT = MiB(u32, 512);
const SIZE_TEMPORARY = MiB(u32, 512);
const SIZE_INCREMENT = MiB(u32, 4);

pub const AllocatorState = struct {
    var Initialized: bool = false;
    var ArenaPermanent: BaseArena = std.mem.zeroes(BaseArena);
    var ArenaTemporary: BaseArena = std.mem.zeroes(BaseArena);
};

// TODO: migrate this to OnInit after restructuring annodue and it can be guaranteed
//  that this OnInit is run before any dependencies
pub fn Init() bool {
    if (AllocatorState.Initialized) return true;
    AllocatorState.ArenaPermanent = BaseArena.Init(SIZE_PERMANENT, SIZE_INCREMENT) orelse return false;
    AllocatorState.ArenaTemporary = BaseArena.Init(SIZE_TEMPORARY, SIZE_INCREMENT) orelse return false;
    AllocatorState.Initialized = true;
    return true;
}

// TODO: migrate this to OnDeinit after restructuring annodue and it can be guaranteed
//  that this OnDeinit is run after all dependencies deinit
pub fn Deinit() void {
    assert(AllocatorState.Initialized);
    AllocatorState.ArenaPermanent.Reset();
    AllocatorState.ArenaTemporary.Reset();
}

pub fn PermanentAllocator() Allocator {
    assert(AllocatorState.Initialized);
    return AllocatorState.ArenaPermanent.Allocator();
}

pub fn TemporaryAllocator() Allocator {
    assert(AllocatorState.Initialized);
    return AllocatorState.ArenaTemporary.Allocator();
}

//------------------------------------------------------------------------------
// annodue hooks

pub fn OnInit(_: *GlobalFn) callconv(.C) void {
    //if (!AllocatorState.Init()) @panic("AMemory(OnInit): OutOfMemory");
}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {
    //AllocatorState.Deinit();
}

pub fn GameLoopB(_: *GlobalFn) callconv(.C) void {
    AllocatorState.ArenaTemporary.Pop();
}

//------------------------------------------------------------------------------
// annodue api

// NOTE: "end of caller lifetime" is phrased vaguely because, although the lifetime
//  is clearly defined now to be annodue's lifetime, in future the plan is to pop
//  this memory in waves based on the "ring" the caller is in. for example, the
//  permanent memory used by a user plugin would be popped when the entire user
//  plugin "ring" is deinitialized, such as when batch reloading all plugins
// TODO: will need to enforce AMemoryGetPermanent/AMemoryGetPermanentZero usage
//  is only during init phases (inits for foundation, each ring and each plugin
//  layer), in order to guarantee that memory is not rugswept during deinit phases

/// allocate memory that is valid until end of caller lifetime
pub fn AMemoryGetPermanent(size: u32) callconv(.C) ?*anyopaque {
    assert(AllocatorState.Initialized);
    var memory = AllocatorState.ArenaPermanent.Push(size);
    return if (memory.len == size) memory.ptr else null;
}

/// allocate zero-ed memory that is valid until end of caller lifetime
pub fn AMemoryGetPermanentZero(size: u32) callconv(.C) ?*anyopaque {
    assert(AllocatorState.Initialized);
    var memory = AllocatorState.ArenaPermanent.PushZero(size);
    return if (memory.len == size) memory.ptr else null;
}

/// allocate memory that is valid until start of next frame
pub fn AMemoryGetTemporary(size: u32) callconv(.C) ?*anyopaque {
    assert(AllocatorState.Initialized);
    var memory = AllocatorState.ArenaTemporary.Push(size);
    return if (memory.len == size) memory.ptr else null;
}

/// allocate zero-ed memory that is valid until start of next frame
pub fn AMemoryGetTemporaryZero(size: u32) callconv(.C) ?*anyopaque {
    assert(AllocatorState.Initialized);
    var memory = AllocatorState.ArenaTemporary.PushZero(size);
    return if (memory.len == size) memory.ptr else null;
}
