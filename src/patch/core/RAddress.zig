//! address range ownership management
//!
//! used to avoid collisions and provide some convenience functions when working
//! within the SWEP1RCR exe addressable range
//!
//! internal dependencies: AMemory

const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const MultiArrayList = std.MultiArrayList;

const w32 = @import("zigwin32");
const PAGE_PROTECTION_FLAGS = w32.system.memory.PAGE_PROTECTION_FLAGS;
const PAGE_EXECUTE_READWRITE = w32.system.memory.PAGE_EXECUTE_READWRITE;
const FALSE = w32.zig.FALSE;
const VirtualProtect = w32.system.memory.VirtualProtect;
const GetLastError = w32.foundation.GetLastError;

const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const mem = @import("../util/memory.zig");

const RACER_IMAGE_SIZE = @import("racer").Meta.IMAGE_SIZE;
const RACER_IMAGE_BASE = @import("racer").Meta.IMAGE_BASE;
const RACER_IMAGE_END = @import("racer").Meta.IMAGE_END;

const RacerSection = struct {
    addr_st: u32,
    addr_ed: u32,
    flags: PAGE_PROTECTION_FLAGS,
};

const RACER_SECTIONS = blk: {
    const section_data = @import("racer").Meta.SECTIONS;
    var sections: [section_data.len]RacerSection = undefined;
    for (section_data, 0..) |s, i| sections[i] = .{
        .addr_st = s[1],
        .addr_ed = s[1] + s[2],
        .flags = @bitCast(s[3]),
    };
    break :blk sections;
};

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
    RangeWriting: ?RangeHandle,

    // FIXME: idk but this is still 11K entries...
    const LIST_CAPACITY = RACER_IMAGE_SIZE / 1024;

    pub fn Init(arena_perm: Allocator, arena_temp: Allocator) ?RangeManager {
        var man: RangeManager = undefined;
        man.ArenaPerm = arena_perm;
        man.ArenaTemp = arena_temp;
        man.GameMemory = arena_perm.alloc(u8, RACER_IMAGE_SIZE) catch return null;
        man.RangeList = .{};
        man.RangeList.ensureTotalCapacity(arena_perm, LIST_CAPACITY) catch return null;
        man.RangeWriting = null;
        return man;
    }

    // NOTE: u32 so it can be be used to check full 32-bit address range
    fn RangeValid(address: u32, end: u32) bool {
        const b_section_ok = RangeSection(address, end) != null;
        return (end > address) and b_section_ok;
    }

    fn RangeSection(address: u32, end: u32) ?u2 {
        for (RACER_SECTIONS, 0..) |section, i|
            if (address >= section.addr_st and end <= section.addr_ed) return @intCast(i);
        return null;
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

    fn RangeGet(self: *const RangeManager, handle: RangeHandle) ?Range {
        const index = self.RangeIndex(handle) orelse return null;
        return self.RangeList.get(index);
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
            if (st == 0) continue; // slot not in use
            if (CollisionStrict1D(u24, address, end, st, ed)) {
                std.log.warn(
                    "RangeAvailable: range {X:0>6}..{X:0>6} collided with {X:0>6}..{X:0>6}",
                    .{ address, end, st, ed },
                );
                return false;
            }
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
        range.Flags = .{ .Section = RangeSection(address, end).? };
        self.RangeList.set(range_i, range);

        const memo_st = address - RACER_IMAGE_BASE;
        const memo_ed = end - RACER_IMAGE_BASE;
        mem.read_bytes(address, &self.GameMemory[memo_st], memo_ed - memo_st);

        return RangeHandle.Init(range.Address, range.Generation);
    }

    /// release an address range, restoring its original contents
    pub fn RangeRelease(self: *RangeManager, handle: RangeHandle) void {
        assert(self.RangeWriting == null);

        const range_i = self.RangeIndex(handle) orelse return;
        var range = self.RangeList.get(range_i);

        const memo_st = range.Address;
        const memo_ed = range.AddressEnd;
        _ = self.RangeWriteBuffer(handle, range.Address, self.GameMemory[memo_st..memo_ed]);

        range.Address = 0;
        range.Flags = std.mem.zeroes(Range.Flags);
        range.Generation += 1;
        self.RangeList.set(range_i, range);
    }

    /// return original contents to memory range
    pub fn RangeRestore(self: *RangeManager, handle: RangeHandle) void {
        assert(self.RangeWriting == null);

        const range = self.RangeGet(handle) orelse return;
        const memo_st = range.Address;
        const memo_ed = range.AddressEnd;
        _ = self.RangeWriteBuffer(handle, range.Address, self.GameMemory[memo_st..memo_ed]);
    }

    pub fn RangeRead(address: u24, end: u24, buffer: []u8) bool {
        assert(end - address == buffer.len);

        if (!RangeValid(address, end)) return false;

        mem.read_bytes(address, buffer.ptr, buffer.len);
        return true;
    }

    /// opens range for writing, ensuring the memory has write permissions.
    /// user must:
    ///  - only open one range for writing at a time
    ///  - close the range by end of plugin callback scope
    ///  - not have any range open during range reserve, release or restore operations
    pub fn RangeWriteSt(self: *RangeManager, handle: RangeHandle) bool {
        if (self.RangeWriting) |_| return false; // already writing

        const range = self.RangeGet(handle) orelse return false; // handle invalid

        var protect: PAGE_PROTECTION_FLAGS = undefined;
        const range_len = range.AddressEnd - range.Address;
        if (FALSE == VirtualProtect(@ptrFromInt(range.Address), range_len, PAGE_EXECUTE_READWRITE, &protect))
            return false;

        self.RangeWriting = handle;
        return true;
    }

    /// closes an address range for writing and restores its normal permissions.
    pub fn RangeWriteEd(self: *RangeManager, handle: RangeHandle) void {
        if (self.RangeWriting == null or !handle.Eql(self.RangeWriting.?)) return; // handle not writing

        const range = self.RangeGet(handle) orelse return; // handle invalid

        var protect: PAGE_PROTECTION_FLAGS = undefined;
        const range_len = range.AddressEnd - range.Address;
        const range_protect = RACER_SECTIONS[range.Flags.Section].flags;
        if (FALSE == VirtualProtect(@ptrFromInt(range.Address), range_len, range_protect, &protect)) return;

        self.RangeWriting = null;
    }

    pub fn RangeWriteBuffer(self: *RangeManager, handle: RangeHandle, addr: u24, buf: []const u8) bool {
        assert(self.RangeWriting == null);

        if (!self.RangeWriteSt(handle)) return false;
        defer self.RangeWriteEd(handle);

        const range = self.RangeGet(handle) orelse return false;
        if (addr < range.Address or addr + buf.len > range.AddressEnd) return false;
        @memcpy(@as([*]u8, @ptrFromInt(addr)), buf);
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
        Section: u2,
        _: u6 = 0,
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

        pub fn Eql(handle: Handle, other: Handle) bool {
            return handle.Address == other.Address and handle.Generation == other.Generation;
        }
    };
};

const RangeHandle = Range.Handle;

pub const RangeHandleOpaque = u32;

comptime {
    assert(RangeHandleOpaque == @typeInfo(RangeHandle).Struct.backing_integer);
}

// TODO: ?? pass enclosed zero-size case (true == CollisionStrict1D(u8, 2, 5, 3, 3))
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
    //try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 3, 3)); // enclosed, zero size
    try std.testing.expect(true == CollisionStrict1D(u8, 2, 5, 2, 5)); // equal
    try std.testing.expect(false == CollisionStrict1D(u8, 2, 2, 2, 2)); // equal both zero
}

//------------------------------------------------------------------------------
// annodue hooks

pub fn OnInit(_: *GlobalFn) callconv(.C) void {}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

pub fn GameLoopB(_: *GlobalFn) callconv(.C) void {
    if (AddressState.Manager.RangeWriting) |handle| {
        const range = AddressState.Manager.RangeGet(handle) orelse panic(
            "RAddress: range handle {X:0>8} closed with write mode left dangling",
            .{@as(RangeHandleOpaque, @bitCast(handle))},
        );

        panic(
            "RAddress: range {X:0>6}..{X:0>6} write mode left dangling",
            .{ range.Address, range.AddressEnd },
        );
    }
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

pub fn RAddressRangeWriteBuffer(handle: RangeHandleOpaque, addr: u32, buf: ?[*]const u8, len: u32) callconv(.C) bool {
    assert(AddressState.Initialized);
    if (buf == null) return false;
    return AddressState.Manager.RangeWriteBuffer(@bitCast(handle), @truncate(addr), buf.?[0..len]);
}

pub fn RAddressRangeWriteSt(handle: RangeHandleOpaque) callconv(.C) bool {
    assert(AddressState.Initialized);
    return AddressState.Manager.RangeWriteSt(@bitCast(handle));
}

pub fn RAddressRangeWriteEd(handle: RangeHandleOpaque) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.RangeWriteEd(@bitCast(handle));
}

pub fn RAddressRangeRestore(handle: RangeHandleOpaque) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.RangeRestore(@bitCast(handle));
}

// update the memoized copy of the address range with the current contents
//pub fn RAddressRangeBackup(handle: RangeHandleOpaque) callconv(.C) void;
