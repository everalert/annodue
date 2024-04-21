const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

// NOTE: source of truth for global allocations, so we don't have to fuck around later
// if we decide to change which allocator or w/e
// TODO: implement alloc(), free(), etc. and make available to global functions api
// TODO: need to be able to free main patch alloc (see: patch.zig) when implementing
// core hot reload
// TODO: defer free all the allocPrint littered about the codebase
// also think more carefully about using allocPrint if it's going to cause all these extra lines

const AllocatorState = struct {
    initialized: bool = false,
    gpa: GeneralPurposeAllocator(.{}) = GeneralPurposeAllocator(.{}){},
    alloc: Allocator = undefined,
};

var ALLOCATOR_STATE: AllocatorState = .{};

pub fn allocator() Allocator {
    if (!ALLOCATOR_STATE.initialized) {
        ALLOCATOR_STATE.alloc = ALLOCATOR_STATE.gpa.allocator();
        ALLOCATOR_STATE.initialized = true;
    }
    return ALLOCATOR_STATE.alloc;
}
