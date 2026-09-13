//! process address range ownership api. used to help guarantee that any range
//! of memory needed for a patch is not already in use.

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

const MemoryContext = @import("../memory.zig").Context;
const MemorySafeContextSt = @import("../memory.zig").SafeContextSt;
const MemorySafeContextEd = @import("../memory.zig").SafeContextEd;
const RoundIntUp = @import("../base/base_math.zig").RoundIntUp;
const CollisionStrict1D = @import("../base/base_math.zig").CollisionStrict1D;
const ProcessImageSlice = @import("../debug/debug.zig").ProcessImageSlice;

comptime {
    assert(builtin.os.tag == .windows); // TODO: OS-agnostic memory abstraction to remove this
    assert(builtin.target.cpu.arch == .x86); // example build command flag:  -target x86-windows
}

// NOTE: nomenclature:
//  Address*        game memory range (outward-facing representation)
//  Range*          internal record of an address range (inward-facing representation)
//  AddressRange*   API endpoint
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
//  - always to/from handle (or directly on st..ed if no ownership involved)

// TODO: ?? consider bitfield for tracking reserved memory as an optimization over
//  searching the whole reserve list for 1D collisions; probably not a perf concern
//  right now, but could be with a lot of live reservations
// TODO: more comprehensive tests, possibly using more sophisticated test runner
//  that actually loads the game
// TODO: only change page permissions for read/write functionality if the section
//  the address range is in doesn't naturally have the read/write flag on

pub const AddressHandleOpaque = u32;
pub const ADDRESS_HANDLE_OPAQUE_NULL: AddressHandleOpaque = 0;

pub const RangeManager = struct {
    /// persistent memory
    Arena: Allocator,

    /// startup-allocated memory range from process image
    ImageSlice: []const u8,
    /// valid regions of memory within image slice. needs not necessarily match
    /// sections in the executable headers; page permissions at load time may be
    /// different to header-defined sections in any case
    ImageSections: []const []const u8,
    /// storage for original contents of an address range at reserve time
    ImageBackup: []u8,

    RangeCount: u32,
    /// benchmarking counter
    RangeCountPeak: u32,

    RangeListHead: *RangeListNode,
    RangeListTail: *RangeListNode,
    RangeListCount: u16,
    /// benchmarking counter
    RangeListCountPeak: u16,
    /// the highest index assignable given the current set of list nodes
    RangeCapacity: u24,

    /// current address range open for writing. only one range can be writing at
    /// a time, to avoid page permission write conflicts
    AddressWriting: AddressHandle,
    AddressWritingCtx: MemoryContext,

    /// option: chunk size for reservation list allocations
    OptListCapacity: u24,

    // NOTE: memory size, list capacity, etc. must remain u24 so that handle can
    //  fit in u32, even if moving to slices
    /// arena memory must be persistent throughout lifetime of resulting RangeManager
    pub fn Init(arena: Allocator, opts: RangeManagerOpts) ?RangeManager {
        const IMAGE_SIZE = @as(u24, @intCast(opts.ImageSlice.len));
        const LIST_CAPACITY = @min(opts.ListCapacity, IMAGE_SIZE + 1);

        const p_image_backup = arena.alloc(u8, IMAGE_SIZE) catch return null;
        const p_list_head = arena.create(RangeListNode) catch return null;

        var man = RangeManager{
            .Arena = arena,
            .ImageSlice = opts.ImageSlice,
            .ImageSections = opts.ImageSections,
            .ImageBackup = p_image_backup,
            .RangeListHead = p_list_head,
            .RangeListTail = p_list_head,
            .RangeCapacity = LIST_CAPACITY,
            .RangeCount = 0, // FIXME: should this just count 1 and include the null obj?
            .RangeCountPeak = 0,
            .RangeListCount = 1,
            .RangeListCountPeak = 1,
            .AddressWriting = AddressHandle.Zero,
            .AddressWritingCtx = undefined,
            .OptListCapacity = LIST_CAPACITY,
        };

        man.RangeListHead.* = .{
            .Data = .{},
            .Prev = null,
            .Next = null,
            .Head = man.RangeListHead,
        };
        man.RangeListHead.Data.setCapacity(arena, LIST_CAPACITY) catch return null;

        // TODO: remove? may not be needed if generation 0 is always invalid
        // reserve index 0 for null object
        const range_null = man.RangeListTail.Data.addOneAssumeCapacity();
        man.RangeListTail.Data.set(range_null, std.mem.zeroes(AddressRange));

        return man;
    }

    pub fn Deinit(self: *RangeManager) void {
        assert(self.AddressWriting.IsNull());

        var i_start: u24 = 0;
        var p_list = self.RangeListHead;
        while (true) : (p_list = p_list.Next orelse break) {
            for (p_list.Data.items(.Flags), i_start..) |f, i| {
                if (!f.Used) continue;
                const ref = RangeRef{ .Node = p_list, .Index = @intCast(i) };
                self.RangeReleaseByRef(ref);
            }
            i_start += @intCast(p_list.Data.len);
        }
    }

    inline fn RangeChunkCountMax(self: *const RangeManager) u24 {
        return RoundIntUp(u24, @as(u24, @intCast(self.ImageSlice.len + 1)), self.OptListCapacity) / self.OptListCapacity;
    }

    inline fn RangeChunkCapacityLast(self: *const RangeManager) u24 {
        return @as(u24, @intCast(self.ImageSlice.len + 1)) % self.OptListCapacity;
    }

    /// creates new chunk of address slots. asserts that the current chunk is
    /// full and that the chunk limit is not reached
    fn RangeChunkNew(self: *RangeManager) ?*RangeListNode {
        const LIST_COUNT_MAX = self.RangeChunkCountMax();
        assert(self.RangeListTail.Next == null);
        assert(self.RangeListTail.Data.len == self.RangeListTail.Data.capacity);
        assert(self.RangeListCount < LIST_COUNT_MAX);
        assert(self.RangeCapacity % self.OptListCapacity == 0);

        const b_final_list = self.RangeListCount + 1 == LIST_COUNT_MAX;
        const new_capacity: u24 = if (!b_final_list) self.OptListCapacity else self.RangeChunkCapacityLast();

        var new_list = self.Arena.create(RangeListNode) catch return null;
        new_list.Data = .{};
        new_list.Data.setCapacity(self.Arena, new_capacity) catch return null;
        new_list.Head = self.RangeListHead;
        new_list.Prev = self.RangeListTail;
        new_list.Next = null;

        self.RangeCapacity += new_capacity;
        self.RangeListTail.Next = new_list;
        self.RangeListTail = new_list;
        self.RangeListCount += 1;
        self.RangeListCountPeak = @max(self.RangeListCount, self.RangeListCountPeak);

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
            if (self.RangeListCount == self.RangeChunkCountMax()) return null;
            p_list = self.RangeChunkNew() orelse return null;
        }

        const i = p_list.Data.addOneAssumeCapacity();
        p_list.Data.set(i, std.mem.zeroes(AddressRange));
        return RangeRef{ .Node = p_list, .Index = @intCast(chunk_start + i) };
    }

    fn AddressSection(self: *const RangeManager, addr_st: u32, addr_ed: u32) ?u16 {
        for (self.ImageSections, 0..) |section, i| {
            const section_st: u32 = @intFromPtr(section.ptr);
            const section_ed: u32 = section_st + section.len;
            if (addr_st >= section_st and addr_ed <= section_ed) return @intCast(i);
        }
        return null;
    }

    fn AddressValid(self: *const RangeManager, addr_st: u32, addr_ed: u32) bool {
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

    /// checks that a range does not collide with existing reserved ranges
    fn AddressAvailable(self: *const RangeManager, addr_st: u32, addr_ed: u32) bool {
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

    fn RangeSpanByHandle(self: *const RangeManager, handle: AddressHandle) AddressSpan {
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
        const memo_st = span.St - @intFromPtr(self.ImageSlice.ptr);
        const memo_ed = span.Ed - @intFromPtr(self.ImageSlice.ptr);
        return self.ImageBackup[memo_st..memo_ed];
    }

    fn AddressReserve(self: *RangeManager, addr_st: u32, addr_ed: u32, owner: u16) AddressHandle {
        const ref = self.RangeRefNew(addr_st, addr_ed) orelse return AddressHandle.Zero;

        var range = self.RangeDataGet(ref);
        range.Generation += 1;
        range.AddressSt = addr_st;
        range.AddressEd = addr_ed;
        range.Flags = .{ .Used = true };
        range.Owner = owner;
        self.RangeDataSet(ref, range);

        self.RangeCount += 1;
        self.RangeCountPeak = @max(self.RangeCount, self.RangeCountPeak);

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

    fn RangeReleaseByHandle(self: *RangeManager, handle: AddressHandle) void {
        const ref = self.RangeRefByHandle(handle) orelse return;
        self.RangeReleaseByRef(ref);
    }

    fn RangeReleaseByOwner(self: *RangeManager, owner: u16) void {
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

    fn RangeRestoreByHandle(self: *RangeManager, handle: AddressHandle) void {
        const ref = self.RangeRefByHandle(handle) orelse return; // handle invalid
        self.RangeRestoreByRef(ref);
    }

    fn AddressRead(self: *const RangeManager, addr_st: u32, addr_ed: u32, buffer: []u8) bool {
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
        self.AddressWritingCtx = MemorySafeContextSt(range.AddressSt, range.AddressEd);
        self.AddressWriting = handle;
        return true;
    }

    fn RangeWriteEdByRef(self: *RangeManager, ref: RangeRef) void {
        const handle = self.RangeHandleByRef(ref);
        assert(!handle.IsNull()); // handle invalid

        if (self.AddressWriting.IsNull() or !handle.Eql(self.AddressWriting)) return; // handle not writing

        MemorySafeContextEd(self.AddressWritingCtx);
        self.AddressWriting = AddressHandle.Zero;
    }

    fn RangeWriteStByHandle(self: *RangeManager, handle: AddressHandle) bool {
        const ref = self.RangeRefByHandle(handle) orelse return false; // handle invalid
        return self.RangeWriteStByRef(ref);
    }

    fn RangeWriteEdByHandle(self: *RangeManager, handle: AddressHandle) void {
        const ref = self.RangeRefByHandle(handle) orelse return;
        self.RangeWriteEdByRef(ref);
    }

    //--------------------------------------------------------------------------
    // API

    /// check an address is within range of the target memory and sections
    pub const AddressRangeValid = AddressValid;

    /// check an address is valid and does not conflict with existing reservations
    pub const AddressRangeAvailable = AddressAvailable;

    /// get the address associated with a handle
    pub const AddressRangeSpan = RangeSpanByHandle;

    /// claim an address and get its reservation handle; returns null handle on failure
    pub const AddressRangeReserve = AddressReserve;

    /// release an address reservation associated with a handle
    pub const AddressRangeRelease = RangeReleaseByHandle;

    /// release all address reservations associated with an owner
    pub const AddressRangeReleaseByOwner = RangeReleaseByOwner;

    /// copy address contents to buffer
    pub const AddressRangeRead = AddressRead;

    /// return original contents to target memory range
    pub const AddressRangeRestore = RangeRestoreByHandle;

    /// opens range for writing, ensuring the memory has write permissions.
    /// user must:
    ///  - only open one range for writing at a time
    ///  - close the range by end of plugin callback scope
    ///  - not have any range open during range reserve, release or restore operations
    pub const AddressRangeWriteSt = RangeWriteStByHandle;

    /// closes an address range for writing and restores its normal permissions.
    pub const AddressRangeWriteEd = RangeWriteEdByHandle;
};

pub const RangeManagerOpts = struct {
    ListCapacity: u24, // limited to size of handle index field
    ImageSlice: []const u8,
    /// slices defining page permission boundaries in the image memory
    ImageSections: []const []const u8,

    pub fn Init(list_capacity: u24, image: []const u8, sections: []const []const u8) RangeManagerOpts {
        assert(image.len <= std.math.maxInt(u24));
        assert(std.math.isPowerOfTwo(list_capacity));
        for (sections) |section| {
            assert(@intFromPtr(section.ptr) >= @intFromPtr(image.ptr));
            assert(@intFromPtr(section.ptr) + section.len <= @intFromPtr(image.ptr) + image.len);
        }

        return RangeManagerOpts{
            .ListCapacity = list_capacity,
            .ImageSlice = image,
            .ImageSections = sections,
        };
    }

    /// init by inspecting running process for main module size and sections. arena
    /// memory must be persistent throughout lifetime of the target RangeManager
    pub fn InitProcess(arena: Allocator, list_capacity: u24, section_capacity: u24) RangeManagerOpts {
        assert(std.math.isPowerOfTwo(list_capacity));
        assert(std.math.isPowerOfTwo(section_capacity));

        const image_slice = ProcessImageSlice();
        var image_sections = arena.alloc([]const u8, section_capacity) catch @panic("InitProcess: OutOfMemory");
        var search_addr = @intFromPtr(image_slice.ptr);
        const search_addr_ed = search_addr + image_slice.len;

        var image_i: u32 = 0;
        while (search_addr < search_addr_ed) {
            if (image_i >= section_capacity) panic(
                "InitProcess: SectionCapacity({d}) exceeded:  base={X:0>8} section={X:0>8}",
                .{ section_capacity, @intFromPtr(image_slice.ptr), search_addr },
            );

            var mbi: MEMORY_BASIC_INFORMATION = undefined;
            if (FALSE == VirtualQuery(@ptrFromInt(search_addr), &mbi, @sizeOf(MEMORY_BASIC_INFORMATION)))
                panic("InitProcess: VirtualQuery: {s} (section {d})", .{ @tagName(GetLastError()), image_i });

            // TODO: skip if section overruns end address? surely not possible if
            //  going through win32 api?
            image_sections[image_i] = @as([*]const u8, @ptrCast(mbi.BaseAddress))[0..mbi.RegionSize];

            image_i += 1;
            search_addr += mbi.RegionSize;
        }

        return RangeManagerOpts{
            .ListCapacity = list_capacity,
            .ImageSlice = image_slice,
            .ImageSections = image_sections[0..image_i],
        };
    }
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
    _: u7 = 0,
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

//------------------------------------------------------------------------------
// tests

// TODO: test range release -> range reserve -> handle differs between them
// TODO: impl more structural approach to test cases
// TODO: more compact basic usage test that is actually readable as an api reference,
//  and move the "extras" to separate tests and make those more thorough
test "Manager: basic usage" {
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;
    const expectEqualSlices = std.testing.expectEqualSlices;

    const MEMORY_REF: [8]u8 = .{ 0, 1, 2, 3, 4, 5, 6, 7 };
    var MEMORY = MEMORY_REF;
    const MEMORY_BASE = @intFromPtr(&MEMORY);
    const MEMORY_SECTIONS: []const []const u8 = &.{ MEMORY[0..4], MEMORY[4..6] };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

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
        arena.allocator(),
        RangeManagerOpts.Init(2, &MEMORY, MEMORY_SECTIONS),
    ) orelse return error.ManagerInitFailed;

    //---------------------------------
    // address range validity

    try expect(false == m.AddressRangeValid(MEMORY_BASE - 1, MEMORY_BASE + 1)); // not in range
    try expect(false == m.AddressRangeValid(MEMORY_BASE + 2, MEMORY_BASE + 6)); // in range, multi-section
    try expect(false == m.AddressRangeValid(MEMORY_BASE + 4, MEMORY_BASE + 8)); // in range, outside section
    try expect(true == m.AddressRangeValid(MEMORY_BASE + 0, MEMORY_BASE + 2)); // in range

    //---------------------------------
    // reservation

    // pass: check and reserve h1
    try expect(true == m.AddressRangeAvailable(A1.St, A1.Ed));
    const h1 = m.AddressRangeReserve(A1.St, A1.Ed, 0);
    try expectEqual(AddressHandle.Init(1, 1), h1);
    try expect(1 == m.RangeCount);
    try expect(1 == m.RangeListCount);

    // fail: overlapping h1
    try expect(false == m.AddressRangeAvailable(A1F.St, A1F.Ed));
    try expectEqual(AddressHandle.Zero, m.AddressRangeReserve(A1F.St, A1F.Ed, 0));
    try expect(1 == m.RangeCount);
    try expect(1 == m.RangeListCount);

    // different owner (1)
    try expect(true == m.AddressRangeAvailable(A2.St, A2.Ed));
    const h2 = m.AddressRangeReserve(A2.St, A2.Ed, 1);
    try expectEqual(AddressHandle.Init(2, 1), h2);
    try expect(2 == m.RangeCount);
    try expect(2 == m.RangeListCount);

    // different section
    try expect(true == m.AddressRangeAvailable(A3.St, A3.Ed));
    const h3 = m.AddressRangeReserve(A3.St, A3.Ed, 0);
    try expectEqual(AddressHandle.Init(3, 1), h3);
    try expect(3 == m.RangeCount);
    try expect(2 == m.RangeListCount);

    // different owner (2)
    try expect(true == m.AddressRangeAvailable(A4.St, A4.Ed));
    const h4 = m.AddressRangeReserve(A4.St, A4.Ed, 2);
    try expectEqual(AddressHandle.Init(4, 1), h4);
    try expect(4 == m.RangeCount);
    try expect(3 == m.RangeListCount);

    //---------------------------------
    // read-write-reset

    // read
    try expect(true == m.AddressRangeRead(A1.St, A1.Ed, r1buf[0..]));
    try expectEqualSlices(u8, r1exp, r1buf[0..]);

    // TODO: test inability to write outside handle's designated address range
    // TODO: test writing indirectly (maybe impl RangeGetSlice?)
    // TODO: test page permissions during and after write
    // write
    try expect(true == m.AddressRangeWriteSt(h1));
    try expect(false == m.AddressWriting.IsNull());
    @memcpy(r1real, w1exp);
    m.AddressRangeWriteEd(h1);
    try expectEqualSlices(u8, w1exp, r1real);
    try expect(true == m.AddressWriting.IsNull());
    r1buf = undefined;

    // restore
    m.AddressRangeRestore(h1);
    try expectEqualSlices(u8, r1exp, r1real);

    //---------------------------------
    // releasing

    // basic release
    m.AddressRangeRelease(h2);
    try expectEqual(@as(u32, 3), m.RangeCount);
    try expect(false == m.AddressRangeWriteSt(h2)); // handle no longer valid = can't write

    // releasing multiple at a time via owner id
    m.AddressRangeReleaseByOwner(0);
    try expect(1 == m.RangeCount);
    try expect(false == m.AddressRangeWriteSt(h1)); // handle no longer valid = can't write
    try expect(false == m.AddressRangeWriteSt(h3)); // handle no longer valid = can't write

    // releasing automatically restores memory
    _ = m.AddressRangeWriteSt(h4);
    @memcpy(r4real, w4exp);
    m.AddressRangeWriteEd(h4);
    try expectEqualSlices(u8, w4exp, r4real);
    m.AddressRangeRelease(h4);
    try expectEqualSlices(u8, r4exp, r4real);
    try expect(0 == m.RangeCount);
    try expect(4 == m.RangeCountPeak);

    // deinit automatically releases all ranges
    _ = m.AddressRangeReserve(A1.St, A1.Ed, 0);
    try expect(1 == m.RangeCount);
    m.Deinit();
    try expect(0 == m.RangeCount);
}
