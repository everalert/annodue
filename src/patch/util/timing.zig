const std = @import("std");
const w = std.os.windows;
const w32 = @import("zigwin32");
const w32f = w32.foundation;
const w32wp = w32.system.windows_programming;

pub extern "ntdll" fn NtSetTimerResolution(
    DesiredResolution: u32,
    SetResolution: bool,
    CurrentResolution: ?*u32,
) callconv(w.WINAPI) w32f.NTSTATUS;

// TIME-BASED SPINLOCK

// FIXME: check for HRT compatibility instead of trying to assign timer repeatedly
// because sleep() sucks, and timeBeginPeriod() is a bad idea
pub const TimeSpinlock = struct {
    min_period: u64 = 1_000_000_000 / 500,
    max_period: u64 = 1_000_000_000 / 10,
    period: u64 = 1_000_000_000 / 24,
    timer: ?std.time.Timer = null,
    timer_res: u32 = 0,
    timer_step: u64 = 0,
    timer_step_cmp: u64 = 0,
    step_excess: u64 = 0,

    pub fn SetPeriod(self: *TimeSpinlock, fps: u32) void {
        self.period = std.math.clamp(1_000_000_000 / fps, self.min_period, self.max_period);
    }

    pub fn Sleep(self: *TimeSpinlock) void {
        if (self.timer == null) {
            var timer_res_min: u32 = std.math.maxInt(u32);
            var timer_res_max: u32 = std.math.maxInt(u32);
            _ = w32wp.NtQueryTimerResolution(&timer_res_max, &timer_res_min, &self.timer_res);
            if (self.timer_res > timer_res_min)
                // FIXME: do we need to unset this on deinit?
                // according to this post, 32bit windows apps under 64bit windows have self-contained timing
                // https://forum.lazarus.freepascal.org/index.php?topic=60029.0
                _ = NtSetTimerResolution(timer_res_min, true, &self.timer_res);

            // FIXME: need to set cmp to like 2ms? for it to be stable, why?
            // just need to add one tick worth of leeway on the value we intend to tick by?
            self.timer_step = @max(self.timer_res * 100, std.time.ns_per_ms); // convert to ns
            self.timer_step_cmp = self.timer_step * 2; // add wiggle room
            self.timer = std.time.Timer.start() catch return;
        }

        const this_period: u64 = self.period - self.step_excess;
        var timer_cur: u64 = self.timer.?.read();
        while (timer_cur < this_period) : (timer_cur = self.timer.?.read()) {
            if (this_period - timer_cur < self.timer_step_cmp) continue;
            std.time.sleep(self.timer_step);
        }

        timer_cur = self.timer.?.lap();
        self.step_excess = @min(timer_cur - this_period, self.period);
    }
};

// RACE TIMER

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
