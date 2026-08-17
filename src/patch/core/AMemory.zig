const std = @import("std");
const assert = std.debug.assert;

const app = @import("../appinfo.zig");
const GlobalFn = app.GLOBAL_FUNCTION;

const BaseArena = @import("../util/base/base_arena.zig");
const MiB = @import("../util/base/base_memory.zig").MiB;

const SIZE_PERMANENT = MiB(u32, 512);
const SIZE_TEMPORARY = MiB(u32, 512);

pub const AllocatorState = struct {
    var Initialized: bool = false;
    var ArenaPermanent: BaseArena = std.mem.zeroes(BaseArena);
    var ArenaTemporary: BaseArena = std.mem.zeroes(BaseArena);
};

// TODO: migrate this to OnInit after restructuring annodue and it can be guaranteed
//  that this OnInit is run before any dependencies
pub fn Init() bool {
    AllocatorState.ArenaPermanent = BaseArena.Init(SIZE_PERMANENT, MiB(u32, 4)) orelse return false;
    AllocatorState.ArenaTemporary = BaseArena.Init(SIZE_TEMPORARY, MiB(u32, 4)) orelse return false;
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

// TODO: deprecate after restructuring annodue such that API can always be used
pub fn PermanentAlloc(size: u32) []u8 {
    return AllocatorState.ArenaPermanent.Push(size);
}

// TODO: deprecate after restructuring annodue such that API can always be used
pub fn PermanentAllocZero(size: u32) []u8 {
    return AllocatorState.ArenaPermanent.PushZero(size);
}

// TODO: deprecate after restructuring annodue such that API can always be used
pub fn TemporaryAlloc(size: u32) []u8 {
    return AllocatorState.ArenaTemporary.Push(size);
}

// TODO: deprecate after restructuring annodue such that API can always be used
pub fn TemporaryAllocZero(size: u32) []u8 {
    return AllocatorState.ArenaTemporary.PushZero(size);
}

//------------------------------------------------------------------------------
// annodue api

// NOTE: "end of caller lifetime" is phrased vaguely because, although the lifetime
//  is clearly defined now to be annodue's lifetime, in future the plan is to pop
//  this memory in waves based on the "ring" the caller is in. for example, the
//  permanent memory used by a user plugin would be popped when the entire user
//  plugin "ring" is deinitialized, such as when batch reloading all plugins

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

//------------------------------------------------------------------------------
// annodue hooks

pub fn OnInit(_: *GlobalFn) callconv(.C) void {
    if (!AllocatorState.Initialized)
        if (!Init()) @panic("failed to initialize AMemory");
}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {
    Deinit();
}

pub fn GameLoopB(_: *GlobalFn) callconv(.C) void {
    AllocatorState.ArenaTemporary.Pop();
}
