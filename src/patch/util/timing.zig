const std = @import("std");
const w = std.os.windows;

// TIME-BASED SPINLOCK

// FIXME: check for HRT compatibility instead of trying to assign timer repeatedly
// because sleep() sucks, and timeBeginPeriod() is a bad idea
pub const TimeSpinlock = struct {
    min_period: u64 = 1_000_000_000 / 500,
    max_period: u64 = 1_000_000_000 / 10,
    period: u64 = 1_000_000_000 / 24,
    timer: ?std.time.Timer = null,

    pub fn SetPeriod(self: *TimeSpinlock, fps: u32) void {
        self.period = std.math.clamp(1_000_000_000 / fps, self.min_period, self.max_period);
    }

    pub fn Sleep(self: *TimeSpinlock) void {
        if (self.timer == null)
            self.timer = std.time.Timer.start() catch return;

        while (self.timer.?.read() < self.period)
            _ = w.kernel32.SwitchToThread();

        _ = self.timer.?.lap();
    }
};

pub const RaceTime = extern struct {
    min: u32,
    sec: u32,
    ms: u32,
};

pub fn RaceTimeFromFloat(t: f32) RaceTime {
    const total_ms: u32 = @as(u32, @intFromFloat(@round(t * 1000)));
    return .{
        .min = total_ms / 60000,
        .sec = (total_ms / 1000) % 60,
        .ms = total_ms % 1000,
    };
}
