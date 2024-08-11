const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const MultiArrayList = std.MultiArrayList;

// https://gist.github.com/gingerBill/7282ff54744838c52cc80c559f697051

pub fn Handle(comptime T: type) type {
    std.debug.assert(@typeInfo(T) == .Int);
    std.debug.assert(@typeInfo(T).Int.signedness == .unsigned);
    std.debug.assert(@typeInfo(T).Int.bits % 8 == 0);

    return extern struct {
        const Self = @This();
        owner: T = 0,
        generation: T = 0,
        index: T = 0,

        pub fn getNull() Self {
            return .{
                .owner = std.math.maxInt(T),
                .generation = std.math.maxInt(T),
                .index = std.math.maxInt(T),
            };
        }

        pub fn isNull(self: *const Self) bool {
            return self.owner == std.math.maxInt(T) and
                self.generation == std.math.maxInt(T) and
                self.index == std.math.maxInt(T);
        }
    };
}

pub fn SparseIndex(comptime T: type) type {
    std.debug.assert(@typeInfo(T) == .Int);
    std.debug.assert(@typeInfo(T).Int.signedness == .unsigned);
    std.debug.assert(@typeInfo(T).Int.bits % 8 == 0);

    return extern struct {
        const Self = @This();
        owner: T = 0,
        generation: T = 0,
        index_or_next: T = 0,

        pub fn getNull() Self {
            return .{
                .owner = std.math.maxInt(T),
                .generation = std.math.maxInt(T),
                .index_or_next = std.math.maxInt(T),
            };
        }

        pub fn isNull(self: *const Self) bool {
            return self.owner == std.math.maxInt(T) and
                self.generation == std.math.maxInt(T) and
                self.index_or_next == std.math.maxInt(T);
        }
    };
}

pub fn HandleMapSOA(comptime T: type, comptime I: type) type {
    return struct {
        const Self = @This();
        const MAX_VALUE = std.math.maxInt(I) - 1;
        handles: ArrayList(Handle(I)),
        values: MultiArrayList(T),
        sparse_indices: ArrayList(SparseIndex(I)),
        next: I,
        alloc: Allocator,

        pub fn init(allocator: Allocator) Self {
            return .{
                .handles = ArrayList(Handle(I)).init(allocator),
                .values = .{},
                .sparse_indices = ArrayList(SparseIndex(I)).init(allocator),
                .next = 0,
                .alloc = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.clear();
            self.handles.deinit();
            self.values.deinit(self.alloc);
            self.sparse_indices.deinit();
        }

        pub fn clear(self: *Self) void {
            self.handles.clearRetainingCapacity();
            self.values.shrinkRetainingCapacity(0);
            self.sparse_indices.clearRetainingCapacity();
            self.next = 0;
        }

        pub fn hasHandle(self: *Self, h: Handle(I)) bool {
            if (h.index < @as(I, @intCast(self.sparse_indices.items.len))) {
                return self.sparse_indices.items[h.index].generation == h.generation and
                    self.sparse_indices.items[h.index].owner == h.owner;
            }
            return false;
        }

        /// get internal array index of data associated with handle
        /// index is also valid for the handle itself
        pub fn getIndex(self: *Self, h: Handle(I)) ?I {
            if (h.index < @as(I, @intCast(self.sparse_indices.items.len))) {
                const entry = self.sparse_indices.items[h.index];
                if (entry.generation == h.generation and entry.owner == h.owner) {
                    return entry.index_or_next;
                }
            }
            return null;
        }

        pub fn get(self: *Self, h: Handle(I)) ?T {
            if (h.index < @as(I, @intCast(self.sparse_indices.items.len))) {
                const entry = self.sparse_indices.items[h.index];
                if (entry.generation == h.generation and entry.owner == h.owner) {
                    return self.values.get(entry.index_or_next);
                }
            }
            return null;
        }

        pub fn insert(self: *Self, owner: I, value: T) !Handle(I) {
            var handle: Handle(I) = undefined;
            if (self.next < @as(I, @intCast(self.sparse_indices.items.len))) {
                var entry = &self.sparse_indices.items[self.next];
                std.debug.assert(entry.generation < MAX_VALUE); // "Generation sparse indices overflow"

                entry.owner = owner;
                entry.generation += 1;
                handle = .{
                    .owner = entry.owner,
                    .generation = entry.generation,
                    .index = self.next,
                };
                self.next = entry.index_or_next;
                entry.index_or_next = @as(I, @intCast(self.handles.items.len));
                try self.handles.append(handle);
                try self.values.append(self.alloc, value);
            } else {
                std.debug.assert(self.next < MAX_VALUE); // "Index sparse indices overflow"

                handle = Handle(I){
                    .owner = owner,
                    .index = @as(I, @intCast(self.sparse_indices.items.len)),
                };
                try self.sparse_indices.append(.{
                    .owner = owner,
                    .index_or_next = @as(I, @intCast(self.handles.items.len)),
                });
                try self.handles.append(handle);
                try self.values.append(self.alloc, value);
                self.next += 1;
            }
            return handle;
        }

        pub fn remove(self: *Self, h: Handle(I)) ?T {
            if (h.index < @as(I, @intCast(self.sparse_indices.items.len))) {
                var entry = &self.sparse_indices.items[h.index];
                if (entry.generation != h.generation) // FIXME: add owner check? also for other handle_maps
                    return null;

                const index = entry.index_or_next;
                entry.generation += 1;
                entry.index_or_next = self.next;
                self.next = h.index;

                _ = self.handles.swapRemove(index);
                const value = self.values.get(index);
                self.values.swapRemove(index);
                if (index < @as(I, @intCast(self.handles.items.len)))
                    self.sparse_indices.items[self.handles.items[index].index].index_or_next = index;

                return value;
            }
            return null;
        }

        pub fn removeOwner(self: *Self, o: I) void {
            const n = self.handles.items.len;
            for (0..n) |i| {
                const h = self.handles.items[n - i - 1];
                if (h.owner == o)
                    _ = self.remove(h);
            }
        }
    };
}

test {
    const T = struct { a: f32, b: u32 };
    const HM = HandleMapSOA(T, u16);
    const H = Handle(u16);

    var m = HM.init(std.testing.allocator);
    defer m.deinit();

    var value: T = .{ .a = 123.456, .b = 123456 };

    var h1: H = try m.insert(123, value);
    var h2: H = try m.insert(456, value);
    var h_: H = h1;
    h_.owner = 789;

    try std.testing.expect(m.hasHandle(h1));
    try std.testing.expect(m.hasHandle(h2));
    try std.testing.expect(!m.hasHandle(h_));

    m.removeOwner(456);
    try std.testing.expect(!m.hasHandle(h2));

    var value_out = m.get(h1);
    try std.testing.expect(value_out != null);
    try std.testing.expectEqual(value, value_out.?);

    _ = m.remove(h1);
    try std.testing.expect(!m.hasHandle(h1));
}
