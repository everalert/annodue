//! swe1r address range ownership api. used to help guarantee that any range of
//! memory needed for a patch is not already in use by another patcher.

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const MultiArrayList = std.MultiArrayList;

const w32 = @import("zigwin32");
const PAGE_PROTECTION_FLAGS = w32.system.memory.PAGE_PROTECTION_FLAGS;
const PAGE_EXECUTE_READWRITE = w32.system.memory.PAGE_EXECUTE_READWRITE;
const MEMORY_BASIC_INFORMATION = w32.system.memory.MEMORY_BASIC_INFORMATION;
const FALSE = w32.zig.FALSE;
const VirtualProtect = w32.system.memory.VirtualProtect;
const VirtualQuery = w32.system.memory.VirtualQuery;
const GetLastError = w32.foundation.GetLastError;

const RoundIntUp = @import("../base/base_math.zig").RoundIntUp;

// TODO: also assert windows? (only necessary because memory-related functions
//  not yet os-agnostic)
comptime {
    assert(builtin.target.cpu.arch == .x86); // example build command flag:  -target x86-windows
}

// NOTE: nomenclature:
//  Address*    = game memory range (outward-facing representation)
//  Range*      = internal record of an address range (inward-facing representation)
// NOTE: structure:
//  general data flow:
//      handle/index -> ref -> work   OR
//      work -> ref -> handle/index
//  - "default"/unlabeled usage is via ref
//  - ref<->index/handle validation is manual on an as-needed basis
//  - main reason for having a distinction between ref and handle is because
//    dereferencing a handle requires a linear search; separating the deref from
//    the data access prevents constantly redoing deref during any api action
//  api (pub functions):
//  - "default"/unlabeled usage is via handle

// TODO: RangeReleaseByRef to release with pre-knowledge of which RangeListNode
//  and index the range is at, to prevent having to constantly iterate over
//  the loop. also need RangeRefByIndex/RangeRefByHandle, and to update any
//  sites that use RangeGetByHandle/RangeGetByIndex (and their code). maybe
//  "by ref" should be the default/unlabeled case? also, "by handle" should be
//  the only pub functions. update: this should be mostly done, just need review
// TODO: cleanup/rework util->memory
// TODO: ?? consider bitfield for tracking reserved memory as an optimization over
//  searching the whole reserve list for 1D collisions; probably not a perf concern
//  right now, but could be with a lot of live reservations

pub const AddressHandleOpaque = u32;
pub const ADDRESS_HANDLE_OPAQUE_NULL: AddressHandleOpaque = 0;

pub const RangeManagerOpts = struct {
    ListCapacity: u24,
    MemorySize: u24,
    MemoryBase: u32, // FIXME: just use a slice, since it's no longer comptime?
    MemorySections: []const SectionInfo,

    pub fn RacerOpts(comptime list_capacity: comptime_int) RangeManagerOpts {
        const r = @import("racer");
        const s = struct {
            // contain to function scope so that racer doesn't need to be imported
            // as a module unless calling this function; easier for testing
            const SECTIONS = blk: {
                var sections: [r.Meta.SECTIONS.len]SectionInfo = undefined;
                for (r.Meta.SECTIONS, 0..) |s, i| sections[i] = .{
                    .memory = @as([*]u8, @ptrFromInt(s[1]))[0..s[2]],
                    .flags = @bitCast(s[3]),
                };
                break :blk sections;
            };
        };

        return RangeManagerOpts{
            .ListCapacity = list_capacity,
            .MemorySize = r.Meta.IMAGE_SIZE,
            .MemoryBase = r.Meta.IMAGE_BASE,
            .MemorySections = &s.SECTIONS,
        };
    }
};

pub const RangeManager = struct {
    ArenaPerm: Allocator,
    ArenaTemp: Allocator,

    /// storage for original contents of an address range at reserve time
    GameMemoryBackup: []u8,

    RangeCount: u32,
    RangeCountMax: u32, // TODO: track peak count for profiling purposes

    RangeListHead: *RangeListNode,
    RangeListTail: *RangeListNode,
    RangeListCount: u16,
    RangeListCountMax: u16, // TODO: track peak count for profiling purposes
    /// the highest index assignable given the current set of list nodes
    RangeCapacity: u24,

    /// current address range open for writing. only one range can be writing at
    /// a time, to avoid page permission write conflicts
    AddressWriting: AddressHandle,

    OptImageSize: u24, // FIXME: can this just be a slice since it's no longer comptime?
    OptImageBase: u32,
    OptImageSections: []const SectionInfo,
    OptListCapacity: u24,
    OptListCapacityLast: u24,
    OptListCountMax: u24,

    // NOTE: API
    // NOTE: memory size, list capacity, etc. must remain u24 so that handle can
    //  fit in u32, even if moving to slices
    // TODO: impl Deinit
    pub fn Init(arena_perm: Allocator, arena_temp: Allocator, opts: RangeManagerOpts) ?RangeManager {
        assert(opts.ListCapacity <= opts.MemorySize + 1); // +1 due to null object
        assert(opts.MemorySize - 2 <= std.math.maxInt(u24)); // -2 due to maxInt offset and null object
        assert(opts.MemorySections.len > 0);
        assert(opts.MemorySections.len <= 4);

        const IMAGE_SIZE = opts.MemorySize;
        const IMAGE_BASE = opts.MemoryBase;
        const IMAGE_SECTIONS = opts.MemorySections;
        const LIST_CAPACITY = opts.ListCapacity;
        const LIST_COUNT_MAX = RoundIntUp(u24, IMAGE_SIZE + 1, LIST_CAPACITY) / LIST_CAPACITY;
        const LIST_CAPACITY_LAST = (IMAGE_SIZE + 1) % LIST_COUNT_MAX; // +1 to account for null object

        const p_game_memory = arena_perm.alloc(u8, IMAGE_SIZE) catch return null;
        const p_list_head = arena_perm.create(RangeListNode) catch return null;

        var man = RangeManager{
            .ArenaPerm = arena_perm,
            .ArenaTemp = arena_temp,
            .GameMemoryBackup = p_game_memory,
            .RangeListHead = p_list_head,
            .RangeListTail = p_list_head,
            .RangeCapacity = LIST_CAPACITY,
            .RangeCount = 0, // FIXME: should this just count 1 and include the null obj?
            .RangeCountMax = 0,
            .RangeListCount = 1,
            .RangeListCountMax = 1,
            .AddressWriting = AddressHandle.Zero,
            .OptImageSize = IMAGE_SIZE,
            .OptImageBase = IMAGE_BASE,
            .OptImageSections = IMAGE_SECTIONS,
            .OptListCapacity = LIST_CAPACITY,
            .OptListCapacityLast = LIST_CAPACITY_LAST,
            .OptListCountMax = LIST_COUNT_MAX,
        };

        man.RangeListHead.* = .{
            .Data = .{},
            .Prev = null,
            .Next = null,
            .Head = man.RangeListHead,
        };
        man.RangeListHead.Data.setCapacity(arena_perm, LIST_CAPACITY) catch return null;

        // reserve index 0 for null object
        const range_null = man.RangeListTail.Data.addOneAssumeCapacity();
        man.RangeListTail.Data.set(range_null, std.mem.zeroes(AddressRange));

        return man;
    }

    /// creates new chunk of address slots. asserts that the current chunk is
    /// full and that the chunk limit is not reached
    fn RangeChunkNew(self: *RangeManager) ?*RangeListNode {
        assert(self.RangeListTail.Next == null);
        assert(self.RangeListTail.Data.len == self.RangeListTail.Data.capacity);
        assert(self.RangeListCount < self.OptListCountMax);
        assert(self.RangeCapacity % self.OptListCapacity == 0);

        const b_final_list = self.RangeListCount + 1 == self.OptListCountMax;
        const new_capacity: u24 = if (b_final_list) self.OptListCapacityLast else self.OptListCapacity;

        var new_list = self.ArenaPerm.create(RangeListNode) catch return null;
        new_list.Data = .{};
        new_list.Data.setCapacity(self.ArenaPerm, new_capacity) catch return null;
        new_list.Head = self.RangeListHead;
        new_list.Prev = self.RangeListTail;
        new_list.Next = null;

        self.RangeCapacity += new_capacity;
        self.RangeListTail.Next = new_list;
        self.RangeListTail = new_list;
        self.RangeListCount += 1;

        return new_list;
    }

    /// find open address slot, creating a new slot and chunk as needed
    /// @return     `null` if address invalid, or already in use
    ///             `null` if no open slots, no remaining chunk capacity and chunk limit reached
    fn RangeRefNew(self: *RangeManager, addr_st: u32, addr_ed: u32) ?RangeRef {
        if (!self.AddressValid(addr_st, addr_ed)) return null;
        if (!self.AddressAvailable(addr_st, addr_ed)) return null;

        var node_i: u32 = 1; // skip null object
        var chunk_start: u32 = 0;
        var p_list = self.RangeListHead;
        while (true) {
            for (
                p_list.Data.items(.Generation)[node_i..],
                p_list.Data.items(.Flags)[node_i..],
                node_i..,
            ) |gen, f, i| {
                if (gen < AddressHandle.MAX_GENERATION and !f.Used) {
                    return RangeRef{ .Node = p_list, .Index = @intCast(chunk_start + i) };
                }
            }

            node_i = 0;
            if (p_list.Data.len == p_list.Data.capacity) chunk_start += p_list.Data.len;
            p_list = p_list.Next orelse break;
        }

        if (p_list.Data.len == p_list.Data.capacity) {
            if (self.RangeListCount == self.OptListCountMax) return null;
            p_list = self.RangeChunkNew() orelse return null;
        }

        const i = p_list.Data.addOneAssumeCapacity();
        p_list.Data.set(i, std.mem.zeroes(AddressRange));
        return RangeRef{ .Node = p_list, .Index = @intCast(chunk_start + i) };
    }

    fn AddressSection(self: *const RangeManager, addr_st: u32, addr_ed: u32) ?u2 {
        for (self.OptImageSections, 0..) |section, i| {
            const section_st: u32 = @intFromPtr(section.memory.ptr);
            const section_ed: u32 = section_st + section.memory.len;
            if (addr_st >= section_st and addr_ed <= section_ed) return @intCast(i);
        }
        return null;
    }

    // NOTE: API
    pub fn AddressValid(self: *const RangeManager, addr_st: u32, addr_ed: u32) bool {
        const b_section_ok = self.AddressSection(addr_st, addr_ed) != null;
        return (addr_ed > addr_st) and b_section_ok;
    }

    /// does not guarantee the range is in use; caller must validate contents
    fn RangeDataGet(self: *const RangeManager, ref: RangeRef) AddressRange {
        assert(ref.Node.Head == self.RangeListHead);
        return ref.Node.Data.get(ref.Index % self.OptListCapacity);
    }

    fn RangeDataSet(self: *const RangeManager, ref: RangeRef, data: AddressRange) void {
        assert(ref.Node.Head == self.RangeListHead);
        ref.Node.Data.set(ref.Index % self.OptListCapacity, data);
    }

    /// returns null if the slot the handle references is not valid
    fn RangeRefByHandle(self: *const RangeManager, handle: AddressHandle) ?RangeRef {
        const ref = self.RangeRefByIndex(handle.Index) orelse return null;
        return if (self.RangeHandleByRef(ref).Eql(handle)) ref else null;
    }

    fn RangeRefByIndex(self: *const RangeManager, index: u24) ?RangeRef {
        if (index >= self.RangeCapacity) return null;
        const list_index = index / self.OptListCapacity;
        const p_list = if (list_index + 1 == self.RangeListCount) self.RangeListTail else blk: {
            var p = self.RangeListHead;
            for (0..list_index) |_| p = p.Next orelse return null;
            break :blk p;
        };
        return RangeRef{ .Node = p_list, .Index = index };
    }

    /// returns null handle if the slot associated with the ref cannot produce a valid handle
    fn RangeHandleByRef(self: *const RangeManager, ref: RangeRef) AddressHandle {
        const flags = ref.Node.Data.items(.Flags)[ref.Index % self.OptListCapacity];
        if (!flags.Used) return AddressHandle.Zero;
        const generation = ref.Node.Data.items(.Generation)[ref.Index % self.OptListCapacity];
        return AddressHandle.Init(ref.Index, generation);
    }

    // TODO: RangeIndexByRef

    // NOTE: API
    /// checks that a range does not collide with existing reserved ranges
    pub fn AddressAvailable(self: *const RangeManager, addr_st: u32, addr_ed: u32) bool {
        if (!self.AddressValid(addr_st, addr_ed)) return false;

        var p_list = self.RangeListHead;
        while (true) : (p_list = p_list.Next orelse break) {
            for (
                p_list.Data.items(.AddressSt),
                p_list.Data.items(.AddressEd),
                p_list.Data.items(.Flags),
            ) |st, ed, f| {
                if (!f.Used) continue;
                if (CollisionStrict1D(u32, addr_st, addr_ed, st, ed)) return false;
            }
        }

        return true;
    }

    fn RangeSpanByRef(self: *const RangeManager, ref: RangeRef) AddressSpan {
        assert(!self.RangeHandleByRef(ref).IsNull()); // range must be in use
        return .{
            .St = ref.Node.Data.items(.AddressSt)[ref.Index % self.OptListCapacity],
            .Ed = ref.Node.Data.items(.AddressEd)[ref.Index % self.OptListCapacity],
        };
    }

    // NOTE: API
    /// get the address associated with a range record
    pub fn RangeSpan(self: *const RangeManager, handle: AddressHandle) AddressSpan {
        const ref = self.RangeRefByHandle(handle) orelse return AddressSpan.Zero;
        return self.RangeSpanByRef(ref);
    }

    fn RangeSliceGetAddress(self: *const RangeManager, ref: RangeRef) []u8 {
        assert(!self.RangeHandleByRef(ref).IsNull()); // range must be in use
        const span = self.RangeSpanByRef(ref);
        const span_len = span.Ed - span.St;
        return @as([*]u8, @ptrFromInt(span.St))[0..span_len];
    }

    fn RangeSliceGetBackup(self: *const RangeManager, ref: RangeRef) []u8 {
        assert(!self.RangeHandleByRef(ref).IsNull()); // range must be in use
        const span = self.RangeSpanByRef(ref);
        const memo_st = span.St - self.OptImageBase;
        const memo_ed = span.Ed - self.OptImageBase;
        return self.GameMemoryBackup[memo_st..memo_ed];
    }

    // NOTE: API
    pub fn RangeReserve(self: *RangeManager, addr_st: u32, addr_ed: u32, owner: u16) AddressHandle {
        const ref = self.RangeRefNew(addr_st, addr_ed) orelse return AddressHandle.Zero;

        var range = self.RangeDataGet(ref);
        range.Generation += 1;
        range.AddressSt = addr_st;
        range.AddressEd = addr_ed;
        range.Flags = .{ .Used = true, .Section = self.AddressSection(addr_st, addr_ed).? };
        range.Owner = owner;
        self.RangeDataSet(ref, range);

        self.RangeCount += 1;

        @memcpy(self.RangeSliceGetBackup(ref), self.RangeSliceGetAddress(ref));

        return AddressHandle.Init(ref.Index, range.Generation);
    }

    /// release an address range, restoring its original contents. does nothing
    /// if the referenced range is not in use
    fn RangeReleaseByRef(self: *RangeManager, ref: RangeRef) void {
        assert(!self.RangeHandleByRef(ref).IsNull()); // range must be in use

        self.RangeRestoreByRef(ref);
        ref.Node.Data.items(.Flags)[ref.Index % self.OptListCapacity].Used = false;
        self.RangeCount -= 1;
    }

    // NOTE: API
    pub fn RangeRelease(self: *RangeManager, handle: AddressHandle) void {
        const ref = self.RangeRefByHandle(handle) orelse return;
        self.RangeReleaseByRef(ref);
    }

    // NOTE: API
    pub fn RangeReleaseByOwner(self: *RangeManager, owner: u16) void {
        assert(self.AddressWriting.IsNull());

        var i_start: u24 = 0;
        var p_list = self.RangeListHead;
        while (true) : (p_list = p_list.Next orelse break) {
            for (
                p_list.Data.items(.Owner),
                p_list.Data.items(.Flags),
                i_start..,
            ) |o, f, i| {
                if (owner != o or !f.Used) continue;
                const ref = RangeRef{ .Node = p_list, .Index = @intCast(i) };
                self.RangeReleaseByRef(ref);
            }
            i_start += @intCast(p_list.Data.len);
        }
    }

    fn RangeRestoreByRef(self: *RangeManager, ref: RangeRef) void {
        assert(!self.RangeHandleByRef(ref).IsNull()); // range must be in use
        assert(self.AddressWriting.IsNull());

        if (self.RangeWriteStByRef(ref)) {
            defer self.RangeWriteEdByRef(ref);
            @memcpy(self.RangeSliceGetAddress(ref), self.RangeSliceGetBackup(ref));
        }
    }

    // NOTE: API
    /// return original contents to memory range
    pub fn RangeRestore(self: *RangeManager, handle: AddressHandle) void {
        const ref = self.RangeRefByHandle(handle) orelse return; // handle invalid
        self.RangeRestoreByRef(ref);
    }

    // NOTE: API
    /// copy address range contents to buffer
    pub fn RangeRead(self: *const RangeManager, addr_st: u32, addr_ed: u32, buffer: []u8) bool {
        assert(addr_ed - addr_st == buffer.len);

        if (!self.AddressValid(addr_st, addr_ed)) return false;

        @memcpy(buffer, @as([*]u8, @ptrFromInt(addr_st)));
        return true;
    }

    fn RangeWriteStByRef(self: *RangeManager, ref: RangeRef) bool {
        const handle = self.RangeHandleByRef(ref);
        assert(!handle.IsNull()); // handle invalid

        if (!self.AddressWriting.IsNull()) return false; // already writing

        const range = self.RangeDataGet(ref);
        var protect: PAGE_PROTECTION_FLAGS = undefined;
        const range_len = range.AddressEd - range.AddressSt;
        if (FALSE == VirtualProtect(@ptrFromInt(range.AddressSt), range_len, PAGE_EXECUTE_READWRITE, &protect))
            return false;

        self.AddressWriting = handle;
        return true;
    }

    fn RangeWriteEdByRef(self: *RangeManager, ref: RangeRef) void {
        const handle = self.RangeHandleByRef(ref);
        assert(!handle.IsNull()); // handle invalid

        if (self.AddressWriting.IsNull() or !handle.Eql(self.AddressWriting)) return; // handle not writing

        const range = self.RangeDataGet(ref);
        var protect: PAGE_PROTECTION_FLAGS = undefined;
        const range_len = range.AddressEd - range.AddressSt;
        const range_protect = self.OptImageSections[range.Flags.Section].flags;
        if (FALSE == VirtualProtect(@ptrFromInt(range.AddressSt), range_len, range_protect, &protect))
            return;

        self.AddressWriting = AddressHandle.Zero;
    }

    // NOTE: API
    /// opens range for writing, ensuring the memory has write permissions.
    /// user must:
    ///  - only open one range for writing at a time
    ///  - close the range by end of plugin callback scope
    ///  - not have any range open during range reserve, release or restore operations
    pub fn RangeWriteSt(self: *RangeManager, handle: AddressHandle) bool {
        const ref = self.RangeRefByHandle(handle) orelse return false; // handle invalid
        return self.RangeWriteStByRef(ref);
    }

    // NOTE: API
    /// closes an address range for writing and restores its normal permissions.
    pub fn RangeWriteEd(self: *RangeManager, handle: AddressHandle) void {
        const ref = self.RangeRefByHandle(handle) orelse return;
        self.RangeWriteEdByRef(ref);
    }
};

const SectionInfo = struct {
    memory: []const u8,
    flags: PAGE_PROTECTION_FLAGS,
};

const RangeListNode = struct {
    Head: *RangeListNode,
    Prev: ?*RangeListNode,
    Next: ?*RangeListNode,
    Data: MultiArrayList(AddressRange),
};

// TODO: also store Generation here?
const RangeRef = struct {
    Node: *RangeListNode,
    /// total address index. do `Index % LIST_CAPACITY` to get local index
    Index: u24,
};

const AddressSpan = struct {
    St: u32,
    Ed: u32,

    const Zero = std.mem.zeroes(AddressSpan);

    pub fn IsNull(self: AddressSpan) bool {
        return self.St == 0 and self.Ed == 0;
    }
};

const AddressRange = struct {
    Generation: u8,
    AddressSt: u32,
    AddressEd: u32,
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

    comptime {
        assert(AddressHandleOpaque == @typeInfo(AddressHandle).Struct.backing_integer);
        assert(@as(AddressHandle, @bitCast(ADDRESS_HANDLE_OPAQUE_NULL)).IsNull());
    }

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

// TODO: impl more structural approach to test cases
// TODO: impl Deinit and test
test "Manager: basic usage" {
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;
    const expectEqualSlices = std.testing.expectEqualSlices;

    const MEMORY_REF: [8]u8 = .{ 0, 1, 2, 3, 4, 5, 6, 7 };
    var MEMORY = MEMORY_REF;
    var MEMORY_INFO: MEMORY_BASIC_INFORMATION = undefined;
    if (FALSE == VirtualQuery(&MEMORY, &MEMORY_INFO, @sizeOf(MEMORY_BASIC_INFORMATION)))
        panic("VirtualQuery: {s}", .{@tagName(GetLastError())});

    const alloc_st = @intFromPtr(MEMORY_INFO.BaseAddress);
    const alloc_ed = alloc_st + MEMORY_INFO.RegionSize;
    const memory_st = @intFromPtr(&MEMORY);
    const memory_ed = memory_st + MEMORY.len;
    assert(alloc_st <= memory_st);
    assert(alloc_ed >= memory_ed);

    const MEMORY_BASE = @intFromPtr(&MEMORY);
    const MEMORY_SIZE = MEMORY.len;
    const MEMORY_SECTIONS: [2]SectionInfo = .{
        SectionInfo{ .memory = MEMORY[0..4], .flags = MEMORY_INFO.AllocationProtect },
        SectionInfo{ .memory = MEMORY[4..6], .flags = MEMORY_INFO.AllocationProtect },
    };

    var arena_perm = std.heap.ArenaAllocator.init(std.testing.allocator);
    var arena_temp = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_perm.deinit();
    defer arena_temp.deinit();

    const A1 = AddressSpan{ .St = MEMORY_BASE + 0, .Ed = MEMORY_BASE + 2 };
    const A1F = AddressSpan{ .St = MEMORY_BASE + 1, .Ed = MEMORY_BASE + 3 };
    const A2 = AddressSpan{ .St = MEMORY_BASE + 2, .Ed = MEMORY_BASE + 4 };
    const A3 = AddressSpan{ .St = MEMORY_BASE + 4, .Ed = MEMORY_BASE + 5 };
    const A4 = AddressSpan{ .St = MEMORY_BASE + 5, .Ed = MEMORY_BASE + 6 };
    var r1buf: [2]u8 = undefined;
    const r1real: []u8 = MEMORY[0..2];
    const r1exp: []const u8 = MEMORY_REF[0..2];
    const w1exp: []const u8 = &.{ 8, 9 };
    comptime assert(!std.mem.eql(u8, r1exp, w1exp));
    const r4real: []u8 = MEMORY[5..6];
    const r4exp: []const u8 = MEMORY_REF[5..6];
    const w4exp: []const u8 = &.{0};
    comptime assert(!std.mem.eql(u8, r4exp, w4exp));

    var m = RangeManager.Init(
        arena_perm.allocator(),
        arena_temp.allocator(),
        RangeManagerOpts{
            .ListCapacity = 2,
            .MemoryBase = MEMORY_BASE,
            .MemorySize = MEMORY_SIZE,
            .MemorySections = &MEMORY_SECTIONS,
        },
    ) orelse return error.ManagerInitFailed;

    //---------------------------------
    // address range validity

    try expect(false == m.AddressValid(MEMORY_BASE - 1, MEMORY_BASE + 1)); // not in range
    try expect(false == m.AddressValid(MEMORY_BASE + 2, MEMORY_BASE + 6)); // in range, multi-section
    try expect(false == m.AddressValid(MEMORY_BASE + 4, MEMORY_BASE + 8)); // in range, outside section
    try expect(true == m.AddressValid(MEMORY_BASE + 0, MEMORY_BASE + 2)); // in range

    //---------------------------------
    // reservation

    // pass: check and reserve h1
    try expect(true == m.AddressAvailable(A1.St, A1.Ed));
    const h1 = m.RangeReserve(A1.St, A1.Ed, 0);
    try expectEqual(AddressHandle.Init(1, 1), h1);
    try expect(1 == m.RangeCount);

    // fail: overlapping h1
    try expect(false == m.AddressAvailable(A1F.St, A1F.Ed));
    try expectEqual(AddressHandle.Zero, m.RangeReserve(A1F.St, A1F.Ed, 0));
    try expect(1 == m.RangeCount);

    // different owner (1)
    try expect(true == m.AddressAvailable(A2.St, A2.Ed));
    const h2 = m.RangeReserve(A2.St, A2.Ed, 1);
    try expectEqual(AddressHandle.Init(2, 1), h2);
    try expect(2 == m.RangeCount);

    // different section
    try expect(true == m.AddressAvailable(A3.St, A3.Ed));
    const h3 = m.RangeReserve(A3.St, A3.Ed, 0);
    try expectEqual(AddressHandle.Init(3, 1), h3);
    try expect(3 == m.RangeCount);

    // different owner (2)
    try expect(true == m.AddressAvailable(A4.St, A4.Ed));
    const h4 = m.RangeReserve(A4.St, A4.Ed, 2);
    try expectEqual(AddressHandle.Init(4, 1), h4);
    try expect(4 == m.RangeCount);

    //---------------------------------
    // read-write-reset

    // read
    try expect(true == m.RangeRead(A1.St, A1.Ed, r1buf[0..]));
    try expectEqualSlices(u8, r1exp, r1buf[0..]);

    // TODO: test inability to write outside handle's designated address range
    // TODO: test writing indirectly (maybe impl RangeGetSlice?)
    // TODO: test page permissions during and after write
    // write
    try expect(true == m.RangeWriteSt(h1));
    try expect(false == m.AddressWriting.IsNull());
    @memcpy(r1real, w1exp);
    m.RangeWriteEd(h1);
    try expectEqualSlices(u8, w1exp, r1real);
    try expect(true == m.AddressWriting.IsNull());
    r1buf = undefined;

    // restore
    m.RangeRestore(h1);
    try expectEqualSlices(u8, r1exp, r1real);

    //---------------------------------
    // releasing

    // basic release
    m.RangeRelease(h2);
    try expectEqual(@as(u32, 3), m.RangeCount);
    try expect(false == m.RangeWriteSt(h2)); // handle no longer valid = can't write

    // releasing multiple at a time via owner id
    m.RangeReleaseByOwner(0);
    try expect(1 == m.RangeCount);
    try expect(false == m.RangeWriteSt(h1)); // handle no longer valid = can't write
    try expect(false == m.RangeWriteSt(h3)); // handle no longer valid = can't write

    // releasing automatically restores memory
    _ = m.RangeWriteSt(h4);
    @memcpy(r4real, w4exp);
    m.RangeWriteEd(h4);
    try expectEqualSlices(u8, w4exp, r4real);
    m.RangeRelease(h4);
    try expectEqualSlices(u8, r4exp, r4real);
    try expect(0 == m.RangeCount);
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
