const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const BoundedArray = std.BoundedArray;

pub fn Handle(comptime T: type) type {
    std.debug.assert(@typeInfo(T) == .Int);
    std.debug.assert(@typeInfo(T).Int.signedness == .unsigned);
    std.debug.assert(@typeInfo(T).Int.bits % 8 == 0);

    return extern struct {
        owner: T = 0,
        generation: T = 0,
        index: T = 0,
    };
}

pub fn SparseIndex(comptime T: type) type {
    std.debug.assert(@typeInfo(T) == .Int);
    std.debug.assert(@typeInfo(T).Int.signedness == .unsigned);
    std.debug.assert(@typeInfo(T).Int.bits % 8 == 0);

    return extern struct {
        owner: T = 0,
        generation: T = 0,
        index_or_next: T = 0,
    };
}

pub fn HandleMapStatic(comptime T: type, comptime I: type, comptime L: usize) type {
    std.debug.assert(@typeInfo(I) == .Int);
    std.debug.assert(L <= std.math.maxInt(I));

    return struct {
        const Self = @This();
        handles: BoundedArray(Handle(I), L),
        values: BoundedArray(T, L),
        sparse_indices: BoundedArray(SparseIndex(I), L),
        next: I,

        pub fn init() !Self {
            return .{
                .handles = try BoundedArray(Handle(I), L).init(0),
                .values = try BoundedArray(T, L).init(0),
                .sparse_indices = try BoundedArray(SparseIndex(I), L).init(0),
                .next = 0,
            };
        }

        pub fn clear(self: *Self) !void {
            try self.handles.resize(0);
            try self.values.resize(0);
            try self.sparse_indices.resize(0);
            self.next = 0;
        }

        pub fn hasHandle(self: *Self, h: Handle(I)) bool {
            if (h.index < @as(I, @intCast(self.sparse_indices.len))) {
                return self.sparse_indices.buffer[h.index].generation == h.generation and
                    self.sparse_indices.buffer[h.index].owner == h.owner;
            }
            return false;
        }

        pub fn isFull(self: *Self) bool {
            return self.next >= L;
        }

        pub fn get(self: *Self, h: Handle(I)) ?*T {
            if (h.index < @as(I, @intCast(self.sparse_indices.len))) {
                const entry = self.sparse_indices.buffer[h.index];
                if (entry.generation == h.generation and entry.owner == h.owner) {
                    return &self.values.buffer[entry.index_or_next];
                }
            }
            return null;
        }

        pub fn insert(self: *Self, value: T) !Handle(I) {
            var handle: Handle(I) = undefined;
            if (self.next < @as(I, @intCast(self.sparse_indices.len))) {
                var entry = &self.sparse_indices.buffer[self.next];
                std.debug.assert(entry.generation < std.math.maxInt(I)); // "Generation sparse indices overflow"

                entry.generation += 1;
                handle = .{
                    .generation = entry.generation,
                    .index = self.next,
                };
                self.next = entry.index_or_next;
                entry.index_or_next = @as(I, @intCast(self.handles.len));
                try self.handles.append(handle);
                try self.values.append(value);
            } else {
                std.debug.assert(self.next < L); // "Index sparse indices overflow"

                handle = Handle(I){
                    .index = @as(I, @intCast(self.sparse_indices.len)),
                };
                try self.sparse_indices.append(.{
                    .index_or_next = @as(I, @intCast(self.handles.len)),
                });
                try self.handles.append(handle);
                try self.values.append(value);
                self.next += 1;
            }
            return handle;
        }

        pub fn remove(self: *Self, h: Handle(I)) ?T {
            if (h.index < @as(I, @intCast(self.sparse_indices.len))) {
                var entry = &self.sparse_indices.buffer[h.index];
                if (entry.generation != h.generation)
                    return null;

                const index = entry.index_or_next;
                entry.generation += 1;
                entry.index_or_next = self.next;
                self.next = h.index;

                _ = self.handles.swapRemove(index);
                const value = self.values.swapRemove(index);
                if (index < @as(I, @intCast(self.handles.len)))
                    self.sparse_indices.buffer[self.handles.buffer[index].index].index_or_next = index;

                return value;
            }
            return null;
        }
    };
}

test {
    const HM = HandleMapStatic(f32, u16, 1);
    const H = Handle(u16);

    var m = try HM.init();
    defer m.clear() catch {};

    var value: f32 = 123.456;

    try std.testing.expect(!m.isFull());
    var h: H = try m.insert(value);

    try std.testing.expect(m.hasHandle(h));
    try std.testing.expect(m.isFull());
    //try std.testing.expectError(error.Overflow, m.insert(value)); // covered by assertion

    var ptr = m.get(h);
    try std.testing.expect(ptr != null);
    try std.testing.expect(ptr.?.* == value);

    _ = m.remove(h);
    try std.testing.expect(!m.hasHandle(h));
    try std.testing.expect(!m.isFull());
}
