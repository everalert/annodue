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

// FIXME: this will return OWNER_CORE_NULL outside of plugin execution context,
//  which may happen in early stages of annodue init. in such cases, the address
//  handle cannot be released by owner id and will only be released manually or
//  by RAddress deinit. for now we can't avoid this in some cases because AHook
//  is in a transitional state, but once annodue api init is moved outside of
//  AHook then we will depend on the api foundation layer and should no longer
//  accept null owners. also, the api should be setup to tell use the owner id
//  directly, so we don't have to do this import at all
const workingOwner = @import("AHook.zig").PluginState.workingOwner;

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
// TODO: ?? consider bitfield for tracking reserved memory as an optimization over
//  searching the whole reserve list for 1D collisions; probably not a perf concern
//  right now, but could be with a lot of live reservations

const RangeManager = struct {
    ArenaPerm: Allocator,
    ArenaTemp: Allocator,

    /// storage for original contents of an address range at reserve time
    GameMemory: []u8, // size: 0xAD0000

    AddressCount: u24,
    AddressList: MultiArrayList(AddressRange),
    /// current address range open for writing. only one range can be writing at
    /// a time, to avoid page permission write conflicts
    AddressWriting: AddressHandle,

    // FIXME: idk but this is still 11K entries...
    const LIST_CAPACITY = RACER_IMAGE_SIZE / 1024;
    const SIZE_MEMORY_GAME = RACER_IMAGE_SIZE;

    pub fn Init(arena_perm: Allocator, arena_temp: Allocator) ?RangeManager {
        var man: RangeManager = undefined;

        man.ArenaPerm = arena_perm;
        man.ArenaTemp = arena_temp;
        man.GameMemory = arena_perm.alloc(u8, SIZE_MEMORY_GAME) catch return null;
        man.AddressWriting = AddressHandle.Zero;
        man.AddressList = .{};
        man.AddressList.ensureTotalCapacity(arena_perm, LIST_CAPACITY) catch return null;
        man.AddressCount = 0;

        // reserve index 0 for null object
        const range_null = man.AddressList.addOneAssumeCapacity();
        man.AddressList.set(range_null, std.mem.zeroes(AddressRange));

        return man;
    }

    fn HandleValid(self: *const RangeManager, handle: AddressHandle) bool {
        if (handle.Index >= self.AddressList.len) return false;
        const range = self.AddressList.get(handle.Index);
        const b_gen_ok = handle.Generation == range.Generation;
        const b_use_ok = range.Flags.Used; // always false for null object
        return b_gen_ok and b_use_ok; // b_idx_ok implicit
    }

    // NOTE: u32 so it can be be used to check full 32-bit address range
    fn RangeValid(addr_st: u32, addr_ed: u32) bool {
        const b_section_ok = RangeSection(addr_st, addr_ed) != null;
        return (addr_ed > addr_st) and b_section_ok;
    }

    fn RangeSection(addr_st: u32, addr_ed: u32) ?u2 {
        for (RACER_SECTIONS, 0..) |section, i|
            if (addr_st >= section.addr_st and addr_ed <= section.addr_ed) return @intCast(i);
        return null;
    }

    fn RangeGet(self: *const RangeManager, handle: AddressHandle) ?AddressRange {
        return if (self.HandleValid(handle)) self.AddressList.get(handle.Index) else null;
    }

    fn RangeGameMemorySlice(self: *const RangeManager, range: *const AddressRange) []u8 {
        const memo_st = range.AddressSt - RACER_IMAGE_BASE;
        const memo_ed = range.AddressEd - RACER_IMAGE_BASE;
        return self.GameMemory[memo_st..memo_ed];
    }

    fn RangeIndexHandle(self: *const RangeManager, index: u24) AddressHandle {
        if (index >= self.AddressList.len) return AddressHandle.Zero;
        if (!self.AddressList.items(.Flags)[index].Used) return AddressHandle.Zero;
        return AddressHandle.Init(index, self.AddressList.items(.Generation)[index]);
    }

    // TODO: merge with RangeReserve? output handle via ptr and return bool whether
    //  the range was actually reserved
    // NOTE: does not check for slot availability, because the plan is to simply
    //  not have that be an issue
    /// checks whether a range is able to be reserved (it doesn't collide with
    /// existing reserved ranges)
    pub fn RangeAvailable(self: *const RangeManager, addr_st: u24, addr_ed: u24) bool {
        if (!RangeValid(addr_st, addr_ed)) return false;

        const slice = self.AddressList.slice();
        const address_st = slice.items(.AddressSt);
        const address_ed = slice.items(.AddressEd);
        const flags = slice.items(.Flags);

        for (address_st, address_ed, flags) |st, ed, f| {
            if (!f.Used) continue;
            if (CollisionStrict1D(u24, addr_st, addr_ed, st, ed)) {
                std.log.warn(
                    "RangeAvailable: range {X:0>6}..{X:0>6} collided with {X:0>6}..{X:0>6}",
                    .{ addr_st, addr_ed, st, ed },
                );
                return false;
            }
        }

        return true;
    }

    pub fn RangeReserve(self: *RangeManager, addr_st: u24, addr_ed: u24, owner: u16) AddressHandle {
        if (!RangeValid(addr_st, addr_ed)) return AddressHandle.Zero;
        if (!self.RangeAvailable(addr_st, addr_ed)) return AddressHandle.Zero;

        const range_i: u32 = blk: {
            const slice = self.AddressList.slice();
            const generation = slice.items(.Generation);
            const flags = slice.items(.Flags);

            for (generation[1..], flags[1..], 1..) |gen, f, i| {
                if (gen < AddressHandle.MAX_GENERATION and !f.Used) break :blk i;
            }

            const i = self.AddressList.addOneAssumeCapacity();
            self.AddressList.set(i, std.mem.zeroes(AddressRange));
            break :blk i;
        };

        var range = self.AddressList.get(range_i);
        range.Generation += 1;
        range.AddressSt = addr_st;
        range.AddressEd = addr_ed;
        range.Flags = .{ .Used = true, .Section = RangeSection(addr_st, addr_ed).? };
        range.Owner = owner;
        self.AddressList.set(range_i, range);

        self.AddressCount += 1;

        @memcpy(self.RangeGameMemorySlice(&range), @as([*]u8, @ptrFromInt(addr_st)));

        return AddressHandle.Init(@truncate(range_i), range.Generation);
    }

    /// release an address range, restoring its original contents
    pub fn RangeRelease(self: *RangeManager, handle: AddressHandle) void {
        assert(self.AddressWriting.IsNull());

        var range = self.RangeGet(handle) orelse return;

        if (self.RangeWriteSt(handle)) {
            defer self.RangeWriteEd(handle);
            @memcpy(@as([*]u8, @ptrFromInt(range.AddressSt)), self.RangeGameMemorySlice(&range));
        }

        range.Flags.Used = false;
        self.AddressList.set(handle.Index, range);

        self.AddressCount -= 1;
    }

    pub fn RangeReleaseOwner(self: *RangeManager, owner: u16) void {
        assert(self.AddressWriting.IsNull());

        const owners = self.AddressList.items(.Owner);
        const flags = self.AddressList.items(.Flags);
        for (owners, flags, 0..) |o, f, i| {
            if (owner != o or !f.Used) continue;
            const handle = self.RangeIndexHandle(@truncate(i));
            self.RangeRelease(handle);
        }
    }

    /// return original contents to memory range
    pub fn RangeRestore(self: *RangeManager, handle: AddressHandle) void {
        assert(self.AddressWriting.IsNull());

        const range = self.RangeGet(handle) orelse return;

        if (self.RangeWriteSt(handle)) {
            defer self.RangeWriteEd(handle);
            @memcpy(@as([*]u8, @ptrFromInt(range.AddressSt)), self.RangeGameMemorySlice(&range));
        }
    }

    pub fn RangeRead(addr_st: u24, addr_ed: u24, buffer: []u8) bool {
        assert(addr_ed - addr_st == buffer.len);

        if (!RangeValid(addr_st, addr_ed)) return false;

        @memcpy(buffer, @as([*]u8, @ptrFromInt(addr_st)));
        return true;
    }

    /// opens range for writing, ensuring the memory has write permissions.
    /// user must:
    ///  - only open one range for writing at a time
    ///  - close the range by end of plugin callback scope
    ///  - not have any range open during range reserve, release or restore operations
    pub fn RangeWriteSt(self: *RangeManager, handle: AddressHandle) bool {
        if (!self.AddressWriting.IsNull()) return false; // already writing

        const range = self.RangeGet(handle) orelse return false; // handle invalid

        var protect: PAGE_PROTECTION_FLAGS = undefined;
        const range_len = range.AddressEd - range.AddressSt;
        if (FALSE == VirtualProtect(@ptrFromInt(range.AddressSt), range_len, PAGE_EXECUTE_READWRITE, &protect))
            return false;

        self.AddressWriting = handle;
        return true;
    }

    /// closes an address range for writing and restores its normal permissions.
    pub fn RangeWriteEd(self: *RangeManager, handle: AddressHandle) void {
        if (self.AddressWriting.IsNull() or !handle.Eql(self.AddressWriting)) return; // handle not writing

        const range = self.RangeGet(handle) orelse return; // handle invalid

        var protect: PAGE_PROTECTION_FLAGS = undefined;
        const range_len = range.AddressEd - range.AddressSt;
        const range_protect = RACER_SECTIONS[range.Flags.Section].flags;
        if (FALSE == VirtualProtect(@ptrFromInt(range.AddressSt), range_len, range_protect, &protect))
            return;

        self.AddressWriting = AddressHandle.Zero;
    }

    pub fn RangeContainsRange(self: *RangeManager, handle: AddressHandle, addr_st: u24, addr_ed: u24) bool {
        if (!RangeValid(addr_st, addr_ed)) return false;
        const range = self.RangeGet(handle) orelse return false;
        return addr_st >= range.AddressSt and addr_ed <= range.AddressEd;
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

const AddressRange = struct {
    Generation: u8,
    AddressSt: u24,
    AddressEd: u24,
    Flags: AddressFlags,
    Owner: u16,
};

const AddressFlags = packed struct(u8) {
    Used: bool,
    Section: u2,
    _: u5 = 0,
};

const AddressHandle = packed struct(u32) {
    Index: u24,
    Generation: u8,

    const MAX_GENERATION = std.math.maxInt(u8);

    // TODO: decl literal, after zig version upgrade
    const Zero = AddressHandle{ .Index = 0, .Generation = 0 };

    pub fn Init(idx: u24, gen: u8) AddressHandle {
        return .{ .Index = idx, .Generation = gen };
    }

    pub fn Eql(handle: AddressHandle, other: AddressHandle) bool {
        return @as(u32, @bitCast(handle)) == @as(u32, @bitCast(other));
    }

    pub fn IsNull(handle: AddressHandle) bool {
        return handle.Eql(Zero);
    }
};

pub const AddressHandleOpaque = u32;
pub const ADDRESS_HANDLE_OPAQUE_NULL: AddressHandleOpaque = 0;

comptime {
    assert(AddressHandleOpaque == @typeInfo(AddressHandle).Struct.backing_integer);
    assert(@as(AddressHandle, @bitCast(ADDRESS_HANDLE_OPAQUE_NULL)).IsNull());
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
    const handle = AddressState.Manager.AddressWriting;
    if (!handle.IsNull()) {
        const range = AddressState.Manager.RangeGet(handle) orelse panic(
            "RAddress: range handle {X:0>8} closed with write mode left dangling",
            .{@as(AddressHandleOpaque, @bitCast(handle))},
        );

        panic(
            "RAddress: range {X:0>6}..{X:0>6} write mode left dangling",
            .{ range.AddressSt, range.AddressEd },
        );
    }
}

pub fn OnPluginDeinitA(owner: u16) callconv(.C) void {
    AddressState.Manager.RangeReleaseOwner(owner);
}

//------------------------------------------------------------------------------
// annodue api

pub fn RAddressRangeAvailable(addr_st: u32, addr_ed: u32) callconv(.C) bool {
    assert(AddressState.Initialized);
    assert(RangeManager.RangeValid(addr_st, addr_ed));
    return AddressState.Manager.RangeAvailable(@truncate(addr_st), @truncate(addr_ed));
}

pub fn RAddressRangeReserve(addr_st: u32, addr_ed: u32) callconv(.C) AddressHandleOpaque {
    assert(AddressState.Initialized);
    assert(RangeManager.RangeValid(addr_st, addr_ed));
    const handle = AddressState.Manager.RangeReserve(@truncate(addr_st), @truncate(addr_ed), workingOwner());
    if (handle.IsNull()) panic(
        "RAddressRangeReserve: range 0x{X:0>6}..0x{X:0>6} cannot be reserved",
        .{ addr_st, addr_ed },
    );
    return @bitCast(handle);
}

pub fn RAddressRangeRelease(handle: AddressHandleOpaque) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.RangeRelease(@bitCast(handle));
}

pub fn RAddressRangeRead(addr_st: u32, addr_ed: u32, buffer: ?[*]u8) callconv(.C) bool {
    assert(AddressState.Initialized);
    assert(RangeManager.RangeValid(addr_st, addr_ed));
    if (buffer == null) return false;
    const buf_sl = buffer.?[0 .. addr_ed - addr_st];
    return RangeManager.RangeRead(@truncate(addr_st), @truncate(addr_ed), buf_sl);
}

pub fn RAddressRangeWriteSt(handle: AddressHandleOpaque) callconv(.C) bool {
    assert(AddressState.Initialized);
    return AddressState.Manager.RangeWriteSt(@bitCast(handle));
}

pub fn RAddressRangeWriteEd(handle: AddressHandleOpaque) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.RangeWriteEd(@bitCast(handle));
}

pub fn RAddressRangeRestore(handle: AddressHandleOpaque) callconv(.C) void {
    assert(AddressState.Initialized);
    AddressState.Manager.RangeRestore(@bitCast(handle));
}

pub fn RAddressRangeContainsRange(handle: AddressHandleOpaque, addr_st: u32, addr_ed: u32) callconv(.C) bool {
    assert(AddressState.Initialized);
    assert(RangeManager.RangeValid(addr_st, addr_ed));
    return AddressState.Manager.RangeContainsRange(@bitCast(handle), @truncate(addr_st), @truncate(addr_ed));
}

// update the memoized copy of the address range with the current contents
//pub fn RAddressRangeBackup(handle: AddressHandleOpaque) callconv(.C) void;
