const mem = @import("memory.zig");

pub const RotatingRGB = struct {
    min: u8 = 95,
    max: u8 = 255,
    rgb: [3]u8 = .{ 255, 95, 95 },
    i: u8 = 0,
    n: u8 = 1,

    pub fn update(self: *RotatingRGB) void {
        self.n = (self.i + 1) % 3;
        if (self.rgb[self.i] == self.min and self.rgb[self.n] == self.max) self.i = self.n;
        self.n = (self.i + 1) % 3;
        if (self.rgb[self.i] == self.max and self.rgb[self.n] < self.max) {
            self.rgb[self.n] += 1;
        } else {
            self.rgb[self.i] -= 1;
        }
    }

    pub fn get(self: *RotatingRGB) u32 {
        var rgb: u32 = 0 | self.rgb[0];
        rgb = rgb << 8 | self.rgb[1];
        rgb = rgb << 8 | self.rgb[2];
        return rgb;
    }

    pub fn new(min: u8, max: u8, i: u8) RotatingRGB {
        return .{
            .min = min,
            .max = max,
            .rgb = .{
                if (i % 3 == 0) min else max,
                if (i % 3 == 1) min else max,
                if (i % 3 == 2) min else max,
            },
            .i = i % 3,
        };
    }
};

// MISC

pub fn PatchRgbArgs(addr: u32, rgba: u32) void {
    _ = mem.write(addr + 1, u8, @as(u8, @truncate(rgba))); // B
    _ = mem.write(addr + 3, u8, @as(u8, @truncate(rgba >> 8))); // G
    _ = mem.write(addr + 5, u8, @as(u8, @truncate(rgba >> 16))); // R
}

pub fn PatchRgbaArgs(addr: u32, rgba: u32) void {
    _ = mem.write(addr + 1, u8, @as(u8, @truncate(rgba))); // A
    _ = mem.write(addr + 3, u8, @as(u8, @truncate(rgba >> 8))); // B
    _ = mem.write(addr + 5, u8, @as(u8, @truncate(rgba >> 16))); // G
    _ = mem.write(addr + 7, u8, @as(u8, @truncate(rgba >> 24))); // R
}
