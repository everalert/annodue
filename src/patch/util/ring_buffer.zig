// RING BUFFER

pub fn RingBuffer(comptime T: type, comptime size: u32) type {
    return extern struct {
        items: [size]T = undefined,
        len: u32 = 0,
        b: i32 = 0,
        f: i32 = 0,

        pub fn push(self: *@This(), in: *const T) bool {
            const next: i32 = @mod(self.f + 1, @as(i32, @intCast(size)));
            if (next == self.b) return false;

            self.items[@intCast(self.f)] = in.*;
            self.f = next;
            self.len = self.used_len();
            return true;
        }

        pub fn pop(self: *@This(), out: ?*T) bool {
            if (self.f == self.b) return false;

            self.f = @mod(self.f - 1, @as(i32, @intCast(size)));
            if (out) |o| o.* = self.items[@intCast(self.f)];
            self.len = self.used_len();
            return true;
        }

        pub fn enqueue(self: *@This(), in: *const T) bool {
            const next: i32 = @mod(self.b - 1, @as(i32, @intCast(size)));
            if (next == self.f) return false;

            self.b = next;
            self.items[@intCast(self.b)] = in.*;
            self.len = self.used_len();
            return true;
        }

        pub fn dequeue(self: *@This(), out: ?*T) bool {
            if (self.f == self.b) return false;

            if (out) |o| o.* = self.items[@intCast(self.b)];
            self.b = @mod(self.b + 1, @as(i32, @intCast(size)));
            self.len = self.used_len();
            return true;
        }

        fn used_len(self: *@This()) u32 {
            return @intCast(@mod(self.f - self.b, size));
        }

        pub fn iterator() void {} // TODO: impl
    };
}
