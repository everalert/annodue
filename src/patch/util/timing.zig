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
    initialized: bool = false,
    min_period: u64 = 1_000_000_000 / 500,
    max_period: u64 = 1_000_000_000 / 10,
    period: u64 = 1_000_000_000 / 24,
    timer: ?std.time.Timer = null,
    timer_step: u32 = 0,
    timer_step_ns: u64 = 0,
    timer_step_cmp: u64 = 0,
    step_excess: u64 = 0,

    pub fn Start(self: *TimeSpinlock) void {
        if (self.initialized) return;
        defer self.initialized = true;

        var caps: w.winmm.TIMECAPS = undefined;
        if (w.winmm.timeGetDevCaps(&caps, 8) != w.winmm.TIMERR_NOERROR) return; // FIXME: error handling
        if (w.winmm.timeBeginPeriod(caps.wPeriodMin) != w.winmm.TIMERR_NOERROR) return; // FIXME: error handling

        self.timer_step = caps.wPeriodMin;
        self.timer_step_ns = self.timer_step * std.time.ns_per_ms; // convert to ns
        self.timer_step_cmp = self.timer_step_ns * 2; // add wiggle room
        self.timer = std.time.Timer.start() catch return;
    }

    // FIXME: probably want to integrate timeBeginPeriod etc. with annodue instead of letting
    // individual plugins handle it; need to actually set that up tho, just doing this for now
    pub fn End(self: *TimeSpinlock) void {
        if (!self.initialized) return;
        defer self.initialized = false;

        if (self.timer_step > 0) _ = w.winmm.timeEndPeriod(self.timer_step); // FIXME: error handling
    }

    pub fn Sleep(self: *TimeSpinlock) void {
        self.Start();

        var period: u64 = if (self.period > self.step_excess) self.period - self.step_excess else self.period;
        var timer_cur: u64 = self.timer.?.read();

        while (timer_cur + self.timer_step_cmp < period) : (timer_cur = self.timer.?.read())
            std.time.sleep(self.timer_step);

        while (timer_cur < period) : (timer_cur = self.timer.?.read())
            continue;

        timer_cur = self.timer.?.lap();
        self.step_excess = timer_cur - period;
    }

    pub fn SetPeriod(self: *TimeSpinlock, fps: u32) void {
        self.period = std.math.clamp(1_000_000_000 / fps, self.min_period, self.max_period);
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
