//! swe1r address range ownership api. used to help guarantee that any range of
//! memory needed for a patch is not already in use by another patcher.

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

const RoundIntUp = @import("../base/base_math.zig").RoundIntUp;

const RACER_IMAGE_SIZE = @import("racer").Meta.IMAGE_SIZE;
const RACER_IMAGE_BASE = @import("racer").Meta.IMAGE_BASE;
const RACER_IMAGE_END = @import("racer").Meta.IMAGE_END;

const RacerSectionInfo = struct {
    addr_st: u32,
    addr_ed: u32,
    flags: PAGE_PROTECTION_FLAGS,
};

const RACER_SECTIONS = blk: {
    const section_data = @import("racer").Meta.SECTIONS;
    var sections: [section_data.len]RacerSectionInfo = undefined;
    for (section_data, 0..) |s, i| sections[i] = .{
        .addr_st = s[1],
        .addr_ed = s[1] + s[2],
        .flags = @bitCast(s[3]),
    };
    break :blk sections;
};

// TODO: RangeReleaseByRef to release with pre-knowledge of which AddressListNode
//  and index the range is at, to prevent having to constantly iterate over
//  the loop. also need RangeRefByIndex/RangeRefByHandle, and to update any
//  sites that use RangeGetByHandle/RangeGetByIndex (and their code). maybe
//  "by ref" should be the default/unlabeled case? also, "by handle" should be
//  the only pub functions. update: this should be mostly done, just need review
// TODO: cleanup/rework util->memory
// TODO: ?? consider bitfield for tracking reserved memory as an optimization over
//  searching the whole reserve list for 1D collisions; probably not a perf concern
//  right now, but could be with a lot of live reservations

pub const RangeManager = struct {
    ArenaPerm: Allocator,
    ArenaTemp: Allocator,

    /// storage for original contents of an address range at reserve time
    GameMemory: []u8, // size: 0xAD0000

    AddressCount: u24,
    AddressCountMax: u24, // TODO: track peak count for profiling purposes

    AddressListHead: *AddressListNode,
    AddressListTail: *AddressListNode,
    AddressListCount: u16,
    AddressListCountMax: u16, // TODO: track peak count for profiling purposes
    /// the highest index assignable given the currently set of list nodes
    AddressIndexMax: u24,

    /// current address range open for writing. only one range can be writing at
    /// a time, to avoid page permission write conflicts
    AddressWriting: AddressHandle,

    const LIST_CAPACITY = 1024;
    const LIST_CAPACITY_LAST = (RACER_IMAGE_SIZE + 1) % LIST_COUNT_MAX; // +1 to account for null object
    const LIST_COUNT_MAX = RoundIntUp(comptime_int, RACER_IMAGE_SIZE + 1, LIST_CAPACITY) / LIST_CAPACITY;

    pub fn Init(arena_perm: Allocator, arena_temp: Allocator) ?RangeManager {
        const p_game_memory = arena_perm.alloc(u8, RACER_IMAGE_SIZE) catch return null;
        const p_list_head = arena_perm.create(AddressListNode) catch return null;

        var man = RangeManager{
            .ArenaPerm = arena_perm,
            .ArenaTemp = arena_temp,
            .GameMemory = p_game_memory,
            .AddressListHead = p_list_head,
            .AddressListTail = p_list_head,
            .AddressIndexMax = LIST_CAPACITY,
            .AddressCount = 0, // FIXME: should this just count 1 and include the null obj?
            .AddressCountMax = 0,
            .AddressListCount = 1,
            .AddressListCountMax = 1,
            .AddressWriting = AddressHandle.Zero,
        };

        man.AddressListHead.* = .{
            .Data = .{},
            .Prev = null,
            .Next = null,
            .Head = man.AddressListHead,
        };
        man.AddressListHead.Data.setCapacity(arena_perm, LIST_CAPACITY) catch return null;

        // reserve index 0 for null object
        const range_null = man.AddressListTail.Data.addOneAssumeCapacity();
        man.AddressListTail.Data.set(range_null, std.mem.zeroes(AddressRange));

        return man;
    }

    // TODO: complementary RangeNew that gets an unused slot and creates a new
    //  slot and address list node as necessary
    fn AddressListNodeNew(self: *RangeManager) ?*AddressListNode {
        assert(self.AddressListCount < LIST_COUNT_MAX);
        assert((self.AddressIndexMax + 1) % LIST_CAPACITY == 0);

        const b_final_list = self.AddressListCount + 1 == LIST_COUNT_MAX;
        const new_capacity: u24 = if (b_final_list) LIST_CAPACITY_LAST else LIST_CAPACITY;

        var new_list = self.ArenaPerm.create(AddressListNode) catch return null;
        new_list.Data = .{};
        new_list.Data.setCapacity(self.ArenaPerm, new_capacity) catch return null;
        new_list.Head = self.AddressListHead;
        new_list.Prev = self.AddressListTail;
        new_list.Next = null;

        self.AddressIndexMax += new_capacity;
        self.AddressListTail.Next = new_list;
        self.AddressListTail = new_list;
        self.AddressListCount += 1;

        return new_list;
    }

    fn HandleValid(self: *const RangeManager, handle: AddressHandle) bool {
        if (handle.Index > self.AddressIndexMax) return false;
        const range = self.RangeGetByIndex(handle.Index) orelse return false;
        const b_gen_ok = handle.Generation == range.Generation;
        const b_use_ok = range.Flags.Used; // always false for null object
        return b_gen_ok and b_use_ok; // b_idx_ok implicit
    }

    fn RangeSection(addr_st: u32, addr_ed: u32) ?u2 {
        for (RACER_SECTIONS, 0..) |section, i|
            if (addr_st >= section.addr_st and addr_ed <= section.addr_ed) return @intCast(i);
        return null;
    }

    // NOTE: u32 so it can be be used to check full 32-bit address range
    pub fn RangeValid(addr_st: u32, addr_ed: u32) bool {
        const b_section_ok = RangeSection(addr_st, addr_ed) != null;
        return (addr_ed > addr_st) and b_section_ok;
    }

    fn RangeRefByHandle(self: *const RangeManager, handle: AddressHandle) ?AddressRef {
        const ref = self.RangeRefByIndex(handle.Index) orelse return null;
        const real_handle = self.RangeHandleByRef(ref);
        return if (handle.Eql(real_handle)) ref else null;
    }

    fn RangeRefByIndex(self: *const RangeManager, index: u24) ?AddressRef {
        const list_index = index / LIST_CAPACITY;
        const p_list = if (list_index + 1 == self.AddressListCount) self.AddressListTail else blk: {
            var p = self.AddressListHead;
            for (0..list_index) |_| p = p.Next orelse return null;
            break :blk p;
        };
        return AddressRef{ .Node = p_list, .Index = index };
    }

    fn RangeGetByRef(self: *const RangeManager, ref: AddressRef) ?AddressRange {
        assert(ref.Node.Head == self.AddressListHead);
        const range = ref.Node.Data.get(ref.Index % LIST_CAPACITY);
        return if (range.Flags.Used) range else null;
    }

    fn RangeSetByRef(self: *const RangeManager, ref: AddressRef, data: AddressRange) void {
        assert(ref.Node.Head == self.AddressListHead);
        ref.Node.Data.set(ref.Index % LIST_CAPACITY, data);
    }

    fn RangeGetByIndex(self: *const RangeManager, index: u24) ?AddressRange {
        const ref = self.RangeRefByIndex(index) orelse return null;
        return self.RangeGetByRef(ref);
    }

    pub fn RangeGetByHandle(self: *const RangeManager, handle: AddressHandle) ?AddressRange {
        return if (self.HandleValid(handle)) self.RangeGetByIndex(handle.Index) else null;
    }

    fn RangeHandleByRef(self: *const RangeManager, ref: AddressRef) AddressHandle {
        const range = self.RangeGetByRef(ref) orelse return AddressHandle.Zero;
        if (!range.Flags.Used) return AddressHandle.Zero;
        return AddressHandle.Init(ref.Index, range.Generation);
    }

    fn RangeHandleByIndex(self: *const RangeManager, index: u24) AddressHandle {
        const range = self.RangeGetByIndex(index) orelse return AddressHandle.Zero;
        if (!range.Flags.Used) return AddressHandle.Zero;
        return AddressHandle.Init(index, range.Generation);
    }

    fn RangeGameMemorySlice(self: *const RangeManager, range: *const AddressRange) []u8 {
        const memo_st = range.AddressSt - RACER_IMAGE_BASE;
        const memo_ed = range.AddressEd - RACER_IMAGE_BASE;
        return self.GameMemory[memo_st..memo_ed];
    }

    /// checks that a range does not collide with existing reserved ranges
    pub fn RangeAvailable(self: *const RangeManager, addr_st: u24, addr_ed: u24) bool {
        if (!RangeValid(addr_st, addr_ed)) return false;

        var p_list = self.AddressListHead;
        while (true) : (p_list = p_list.Next orelse break) {
            for (
                p_list.Data.items(.AddressSt),
                p_list.Data.items(.AddressEd),
                p_list.Data.items(.Flags),
            ) |st, ed, f| {
                if (!f.Used) continue;
                if (CollisionStrict1D(u24, addr_st, addr_ed, st, ed)) return false;
            }
        }

        return true;
    }

    pub fn RangeReserve(self: *RangeManager, addr_st: u24, addr_ed: u24, owner: u16) AddressHandle {
        if (!RangeValid(addr_st, addr_ed)) return AddressHandle.Zero;
        if (!self.RangeAvailable(addr_st, addr_ed)) return AddressHandle.Zero;

        const range_i: u32 = blk: {
            var p_list = self.AddressListHead;
            var i_start: usize = 1; // skip null object
            while (true) : (p_list = p_list.Next orelse break) {
                for (
                    p_list.Data.items(.Generation)[i_start..],
                    p_list.Data.items(.Flags)[i_start..],
                    i_start..,
                ) |gen, f, i| {
                    if (gen < AddressHandle.MAX_GENERATION and !f.Used) break :blk i;
                }

                i_start = 0;
            }

            if (p_list.Data.len == p_list.Data.capacity) {
                if (self.AddressListCount == LIST_COUNT_MAX) return AddressHandle.Zero;
                p_list = self.AddressListNodeNew() orelse return AddressHandle.Zero;
            }

            const i = p_list.Data.addOneAssumeCapacity();
            p_list.Data.set(i, std.mem.zeroes(AddressRange));
            break :blk i;
        };

        var range = self.AddressListTail.Data.get(range_i);
        range.Generation += 1;
        range.AddressSt = addr_st;
        range.AddressEd = addr_ed;
        range.Flags = .{ .Used = true, .Section = RangeSection(addr_st, addr_ed).? };
        range.Owner = owner;
        self.AddressListTail.Data.set(range_i, range);

        self.AddressCount += 1;

        @memcpy(self.RangeGameMemorySlice(&range), @as([*]u8, @ptrFromInt(addr_st)));

        return AddressHandle.Init(@truncate(range_i), range.Generation);
    }

    pub fn RangeRelease(self: *RangeManager, handle: AddressHandle) void {
        const ref = self.RangeRefByHandle(handle) orelse return;
        self.RangeReleaseByRef(ref);
    }

    /// release an address range, restoring its original contents
    pub fn RangeReleaseByRef(self: *RangeManager, ref: AddressRef) void {
        assert(self.AddressWriting.IsNull());

        var range = self.RangeGetByRef(ref) orelse return;

        if (self.RangeWriteStByRef(ref)) {
            defer self.RangeWriteEdByRef(ref);
            @memcpy(@as([*]u8, @ptrFromInt(range.AddressSt)), self.RangeGameMemorySlice(&range));
        }

        range.Flags.Used = false;
        self.RangeSetByRef(ref, range);

        self.AddressCount -= 1;
    }

    pub fn RangeReleaseOwner(self: *RangeManager, owner: u16) void {
        assert(self.AddressWriting.IsNull());

        var p_list = self.AddressListHead;
        while (true) : (p_list = p_list.Next orelse break) {
            for (
                p_list.Data.items(.Owner),
                p_list.Data.items(.Flags),
                0..,
            ) |o, f, i| {
                if (owner != o or !f.Used) continue;
                const handle = self.RangeHandleByIndex(@truncate(i));
                self.RangeRelease(handle);
            }
        }
    }

    /// return original contents to memory range
    pub fn RangeRestore(self: *RangeManager, handle: AddressHandle) void {
        assert(self.AddressWriting.IsNull());

        const range = self.RangeGetByHandle(handle) orelse return;

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

    fn RangeWriteStByRef(self: *RangeManager, ref: AddressRef) bool {
        if (!self.AddressWriting.IsNull()) return false; // already writing

        const range = self.RangeGetByRef(ref) orelse return false;

        var protect: PAGE_PROTECTION_FLAGS = undefined;
        const range_len = range.AddressEd - range.AddressSt;
        if (FALSE == VirtualProtect(@ptrFromInt(range.AddressSt), range_len, PAGE_EXECUTE_READWRITE, &protect))
            return false;

        self.AddressWriting = self.RangeHandleByIndex(ref.Index);
        return true;
    }

    /// opens range for writing, ensuring the memory has write permissions.
    /// user must:
    ///  - only open one range for writing at a time
    ///  - close the range by end of plugin callback scope
    ///  - not have any range open during range reserve, release or restore operations
    pub fn RangeWriteSt(self: *RangeManager, handle: AddressHandle) bool {
        const ref = self.RangeRefByHandle(handle) orelse return false; // handle invalid
        return self.RangeWriteStByRef(ref);
    }

    // mirrored from `WriteSt*` because `AddressWriting` logic works more naturally
    fn RangeWriteEdByRef(self: *RangeManager, ref: AddressRef) void {
        const handle = self.RangeHandleByRef(ref);
        self.RangeWriteEd(handle);
    }

    /// closes an address range for writing and restores its normal permissions.
    pub fn RangeWriteEd(self: *RangeManager, handle: AddressHandle) void {
        if (self.AddressWriting.IsNull() or !handle.Eql(self.AddressWriting)) return; // handle not writing

        const range = self.RangeGetByHandle(handle) orelse return; // handle invalid

        var protect: PAGE_PROTECTION_FLAGS = undefined;
        const range_len = range.AddressEd - range.AddressSt;
        const range_protect = RACER_SECTIONS[range.Flags.Section].flags;
        if (FALSE == VirtualProtect(@ptrFromInt(range.AddressSt), range_len, range_protect, &protect))
            return;

        self.AddressWriting = AddressHandle.Zero;
    }
};

const AddressListNode = struct {
    Head: *AddressListNode,
    Prev: ?*AddressListNode,
    Next: ?*AddressListNode,
    Data: MultiArrayList(AddressRange),
};

// TODO: also store Generation here?
const AddressRef = struct {
    Node: *AddressListNode,
    /// total address index. do `Index % LIST_CAPACITY` to get local index
    Index: u24,
};

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
