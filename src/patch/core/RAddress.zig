//! game address range ownership/collision management api
//!
//! see libannodue->api->helpers for related convenience and compound functions.
//!
//! internal dependencies: AMemory

// TODO: ?? add api endpoint for updating backup copy of a memory range with the
//  current contents in memory?

const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;

const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const core_address = @import("../util/core/core_address.zig");
const RangeManagerOpts = core_address.RangeManagerOpts;
const RangeManager = core_address.RangeManager;
const AddressHandle = core_address.AddressHandleOpaque;
const ADDRESS_HANDLE_NULL = core_address.ADDRESS_HANDLE_OPAQUE_NULL;

// FIXME: this will return OWNER_CORE_NULL outside of plugin execution context,
//  which may happen in early stages of annodue init. in such cases, the address
//  handle cannot be released by owner id and will only be released manually or
//  by RAddress deinit. for now we can't avoid this in some cases because AHook
//  is in a transitional state, but once annodue api init is moved outside of
//  AHook then we will depend on the api foundation layer and should no longer
//  accept null owners. also, the api should be setup to tell use the owner id
//  directly, so we don't have to do this import at all
const WorkingOwner = @import("AHook.zig").PluginState.WorkingOwner;

const AddressState = struct {
    var Initialized: bool = false;
    var Manager: RangeManager = undefined;
};

pub fn Init(arena_perm: Allocator) void {
    AddressState.Initialized = true;
    AddressState.Manager = RangeManager.Init(
        arena_perm,
        RangeManagerOpts.InitProcess(arena_perm, 1024, 64),
    ) orelse @panic("RAddress.Init: OutOfMemory");
}

//------------------------------------------------------------------------------
// annodue hooks

pub fn OnInit(_: *GlobalFn) callconv(.C) void {}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

pub fn GameLoopB(_: *GlobalFn) callconv(.C) void {
    const handle = AddressState.Manager.AddressWriting;
    if (!handle.IsNull()) {
        const span = AddressState.Manager.AddressRangeSpan(handle);
        if (span.IsNull()) panic(
            "RAddress: range handle {X:0>8} closed with write mode left dangling",
            .{@as(AddressHandle, @bitCast(handle))},
        );

        panic("RAddress: range {X:0>6}..{X:0>6} write mode left dangling", .{ span.St, span.Ed });
    }
}

pub fn OnPluginDeinitA(owner: u16) callconv(.C) void {
    AddressState.Manager.AddressRangeReleaseByOwner(owner);
}

//------------------------------------------------------------------------------
// annodue api

// NOTE: asserting range validity and availability prioritized over "graceful"
//  failure. internal development should reserve upfront so that collisions are
//  assertion-checked and caught early. plugin authors requiring a "graceful"
//  option should check for availability first; in this case validity will still
//  be asserted.

inline fn AssertAddressValid(addr_st: u32, addr_ed: u32) void {
    if (!AddressState.Manager.AddressRangeValid(addr_st, addr_ed)) panic(
        "RAddressRangeReserve: range 0x{X:0>6}..0x{X:0>6} invalid",
        .{ addr_st, addr_ed },
    );
}

pub fn RAddressRangeAvailable(addr_st: u32, addr_ed: u32) callconv(.C) bool {
    assert(AddressState.Initialized);
    AssertAddressValid(addr_st, addr_ed);
    return AddressState.Manager.AddressRangeAvailable(addr_st, addr_ed);
}

pub fn RAddressRangeReserve(addr_st: u32, addr_ed: u32) callconv(.C) AddressHandle {
    assert(AddressState.Initialized);
    AssertAddressValid(addr_st, addr_ed);
    const handle = AddressState.Manager.AddressRangeReserve(addr_st, addr_ed, WorkingOwner());
    if (handle.IsNull()) panic(
        "RAddressRangeReserve: range 0x{X:0>6}..0x{X:0>6} cannot be reserved",
        .{ addr_st, addr_ed },
    );
    return @bitCast(handle);
}

pub fn RAddressRangeRelease(handle: AddressHandle) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.AddressRangeRelease(@bitCast(handle));
}

pub fn RAddressRangeRead(addr_st: u32, addr_ed: u32, buffer: ?[*]u8) callconv(.C) bool {
    assert(AddressState.Initialized);
    AssertAddressValid(addr_st, addr_ed);
    if (buffer == null) return false;
    const buf_sl = buffer.?[0 .. addr_ed - addr_st];
    return AddressState.Manager.AddressRangeRead(addr_st, addr_ed, buf_sl);
}

pub fn RAddressRangeWriteSt(handle: AddressHandle) callconv(.C) bool {
    assert(AddressState.Initialized);
    return AddressState.Manager.AddressRangeWriteSt(@bitCast(handle));
}

pub fn RAddressRangeWriteEd(handle: AddressHandle) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.AddressRangeWriteEd(@bitCast(handle));
}

pub fn RAddressRangeRestore(handle: AddressHandle) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.AddressRangeRestore(@bitCast(handle));
}

pub fn RAddressRangeContainsRange(handle: AddressHandle, addr_st: u32, addr_ed: u32) callconv(.C) bool {
    assert(AddressState.Initialized);
    AssertAddressValid(addr_st, addr_ed);
    const span = AddressState.Manager.AddressRangeSpan(@bitCast(handle));
    if (span.IsNull()) return false;
    return addr_st >= span.St and addr_ed <= span.Ed;
}
