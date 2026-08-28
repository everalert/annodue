//! address range ownership management
//!
//! used to avoid collisions and provide some convenience functions when working
//! within the SWEP1RCR exe addressable range

const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const MultiArrayList = std.MultiArrayList;

const mem = @import("../util/memory.zig");

const RACER_IMAGE_SIZE = @import("racer").Meta.IMAGE_SIZE;
const RACER_IMAGE_BASE = @import("racer").Meta.IMAGE_BASE;
const RACER_IMAGE_END = @import("racer").Meta.IMAGE_END;

// TODO: expanding range list capacity; expand in non-reallocated chunks so that
//  older arena allocations don't need to be made redundant
// TODO: range entries need to be associated with a plugin, so they can auto-release
//  when the plugin deinits. also: impl the auto-release
// TODO: clean up util/memory and migrate to a "real" libannodue location/section

const RangeManager = struct {
    ArenaPerm: Allocator,
    ArenaTemp: Allocator,

    /// storage for original contents of an address range at reserve time
    GameMemory: []u8,

    RangeList: MultiArrayList(Range),

    // FIXME: idk but this is still 11K entries...
    const LIST_CAPACITY = RACER_IMAGE_SIZE / 1024;

    pub fn Init(arena_perm: Allocator, arena_temp: Allocator) ?RangeManager {
        var man: RangeManager = undefined;
        man.ArenaPerm = arena_perm;
        man.ArenaTemp = arena_temp;
        man.GameMemory = arena_perm.alloc(u8, RACER_IMAGE_SIZE) catch return null;
        man.RangeList = .{};
        man.RangeList.ensureTotalCapacity(arena_perm, LIST_CAPACITY) catch return null;
        return man;
    }

    // u32 so it can be be used to check full 32-bit address range
    fn RangeValid(address: u32, end: u32) bool {
        return (end > address) and (address >= RACER_IMAGE_BASE) and (end <= RACER_IMAGE_END);
    }

    fn RangeIndex(self: *const RangeManager, handle: RangeHandle) ?u32 {
        const slice = self.RangeList.slice();
        const generation = slice.items(.Generation);
        const address_st = slice.items(.Address);

        for (generation, address_st, 0..) |gen, st, i| {
            if (st == handle.Address and gen == handle.Generation) return i;
        }

        return null; // handle doesn't exist
    }

    // TODO: merge with RangeReserve? output handle via ptr and return bool whether
    //  the range was actually reserved
    // NOTE: does not check for slot availability, because the plan is to simply
    //  not have that be an issue
    /// checks whether a range is able to be reserved (it doesn't collide with
    /// existing reserved ranges)
    pub fn RangeAvailable(self: *const RangeManager, address: u24, end: u24) bool {
        if (!RangeValid(address, end)) return false;

        const slice = self.RangeList.slice();
        const address_st = slice.items(.Address);
        const address_ed = slice.items(.AddressEnd);

        for (address_st, address_ed) |st, ed| {
            if (CollisionStrict1D(u24, address, end, st, ed)) return false;
        }

        return true;
    }

    pub fn RangeReserve(self: *RangeManager, address: u24, end: u24) ?RangeHandle {
        if (!RangeValid(address, end)) return null;
        if (!self.RangeAvailable(address, end)) return null;

        const range_i: u32 = blk: {
            const slice = self.RangeList.slice();
            const generation = slice.items(.Generation);
            const address_st = slice.items(.Address);

            for (generation, address_st, 0..) |gen, st, i| {
                if (RangeHandle.Available(st, gen)) break :blk i;
            }

            const i = self.RangeList.addOneAssumeCapacity();
            self.RangeList.set(i, std.mem.zeroes(Range));
            break :blk i;
        };

        var range = self.RangeList.get(range_i);
        range.Address = address;
        range.AddressEnd = end;
        self.RangeList.set(range_i, range);

        const memo_st = address - RACER_IMAGE_BASE;
        const memo_ed = end - RACER_IMAGE_BASE;
        mem.read_bytes(address, &self.GameMemory[memo_st], memo_ed - memo_st);

        return RangeHandle.Init(range.Address, range.Generation);
    }

    // TODO: close writing if needed
    pub fn RangeRelease(self: *RangeManager, handle: RangeHandle) void {
        const range_i = self.RangeIndex(handle) orelse return;
        var range = self.RangeList.get(range_i);

        const memo_st = range.Address;
        const memo_ed = range.AddressEnd;
        _ = mem.write_bytes(memo_st, self.GameMemory[memo_st..memo_ed]);

        range.Address = 0;
        range.Flags = std.mem.zeroes(Range.Flags);
        range.Generation += 1;
        self.RangeList.set(range_i, range);
    }

    // TODO: assert writing is closed
    pub fn RangeRestore(self: *RangeManager, handle: RangeHandle) void {
        const range_i = self.RangeIndex(handle) orelse return;
        const range = self.RangeList.get(range_i);

        const memo_st = range.Address;
        const memo_ed = range.AddressEnd;
        _ = mem.write_bytes(memo_st, self.GameMemory[memo_st..memo_ed]);
    }

    pub fn RangeRead(address: u24, end: u24, buffer: []u8) bool {
        assert(end - address == buffer.len);

        if (!RangeValid(address, end)) return false;

        mem.read_bytes(address, buffer.ptr, buffer.len);
        return true;
    }
};

const AddressState = struct {
    var Initialized: bool = false;
    var Manager: RangeManager = undefined;
};

pub fn Init(arena_perm: Allocator, arena_temp: Allocator) void {
    AddressState.Manager = RangeManager.Init(arena_perm, arena_temp) orelse @panic("RAddress.Init: OutOfMemory");
    AddressState.Initialized = true;
}

const Range = packed struct {
    Address: u24,
    AddressEnd: u24,
    Generation: u8,
    Flags: Flags,

    const Flags = packed struct(u8) {
        bWriteOpen: bool,
        _: u7,
    };

    const Handle = packed struct(u32) {
        Address: u24,
        Generation: u8,

        pub fn Init(addr: u24, gen: u8) Handle {
            return .{ .Address = addr, .Generation = gen };
        }

        pub fn Available(addr: u24, gen: u8) bool {
            return addr == 0 and gen < std.math.maxInt(@TypeOf(gen));
        }
    };
};

const RangeHandle = Range.Handle;

pub const RangeHandleOpaque = u32;

comptime {
    assert(RangeHandleOpaque == @typeInfo(RangeHandle).Struct.backing_integer);
}

// FIXME: move to libannodue under base_vector or something
/// slice-style collision check, where n2 values represent first integer
/// value that is out-of-range (i.e. a2==b1 is not a collision)
fn CollisionStrict1D(comptime T: type, a1: T, a2: T, b1: T, b2: T) bool {
    assert(a1 <= a2);
    assert(b1 <= b2);
    const st_max = @max(a1, b1);
    const ed_min = @min(a2, b2);
    return st_max < ed_min or ed_min > st_max;
}

test "CollisionStrict1D" {
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 5, 1, 2)); // outside left
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 5, 5, 6)); // outside right
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 5, 2, 2)); // zero-length left
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 5, 5, 5)); // zero-length right
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 1, 3)); // partial left
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 4, 6)); // partial right
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 1, 6)); // encompassing
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 3, 4)); // enclosed
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 2, 5)); // equal
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 2, 2, 2)); // equal both zero
}

//------------------------------------------------------------------------------
// annodue api

pub fn RAddressRangeAvailable(address: u32, end: u32) callconv(.C) bool {
    assert(AddressState.Initialized);
    assert(RangeManager.RangeValid(address, end));
    return AddressState.Manager.RangeAvailable(@truncate(address), @truncate(end));
}

pub fn RAddressRangeReserve(address: u32, end: u32) callconv(.C) RangeHandleOpaque {
    assert(AddressState.Initialized);
    assert(RangeManager.RangeValid(address, end));
    const handle = AddressState.Manager.RangeReserve(@truncate(address), @truncate(end));
    if (handle) |h| return @bitCast(h) else panic(
        "RAddressRangeReserve: range 0x{X:0>6}..0x{X:0>6} cannot be reserved",
        .{ address, end },
    );
}

pub fn RAddressRangeRelease(handle: RangeHandleOpaque) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.RangeRelease(@bitCast(handle));
}

pub fn RAddressRangeRead(address: u32, end: u32, buffer: ?[*]u8) callconv(.C) bool {
    assert(AddressState.Initialized);
    assert(RangeManager.RangeValid(address, end));
    if (buffer == null) return false;
    const buf_sl = buffer.?[0 .. end - address];
    return RangeManager.RangeRead(@truncate(address), @truncate(end), buf_sl);
}

pub fn RAddressRangeWrite(handle: RangeHandleOpaque) callconv(.C) void {
    _ = handle;
    assert(AddressState.Initialized);
    @panic("not implemented");
}

pub fn RAddressRangeWriteSt(handle: RangeHandleOpaque) callconv(.C) void {
    _ = handle;
    assert(AddressState.Initialized);
    @panic("not implemented");
}

pub fn RAddressRangeWriteEd(handle: RangeHandleOpaque) callconv(.C) void {
    _ = handle;
    assert(AddressState.Initialized);
    @panic("not implemented");
}

pub fn RAddressRangeRestore(handle: RangeHandleOpaque) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.RangeRestore(@bitCast(handle));
}

// update the memoized copy of the address range with the current contents
//pub fn RAddressRangeBackup(handle: RangeHandleOpaque) callconv(.C) void;
