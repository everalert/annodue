const std = @import("std");
const w = std.os.windows;
const BOOL = w.BOOL;

// TODO: confirm b32 stuff works with bool def

// GAME FUNCTIONS

pub const Time_Tick: *fn () callconv(.C) void = @ptrFromInt(0x480540);
pub const Time_SetFixedFrametime: *fn (frametime: f64) callconv(.C) void = @ptrFromInt(0x480480);
pub const Time_SetStopped: *fn (stopped: bool) callconv(.C) void = @ptrFromInt(0x4804B0); // b32

// GAME CONSTANTS

pub const TIMESTAMP: *u32 = @ptrFromInt(0x50CB60);
pub const STOPPED: *BOOL = @ptrFromInt(0x50CB64);
pub const FIXED_STEP_ON: *BOOL = @ptrFromInt(0x50CB68);
pub const FIXED_FRAMETIME: *f64 = @ptrFromInt(0x50CB70);

pub const FRAMECOUNT: *u32 = @ptrFromInt(0xE22A30);
pub const TOTALTIME: *f64 = @ptrFromInt(0xE22A38);
pub const FRAMETIME_64: *f64 = @ptrFromInt(0xE22A40);
pub const FRAMETIME_64_RAW: *f64 = @ptrFromInt(0xE22A48);
pub const FRAMETIME: *f32 = @ptrFromInt(0xE22A50);

pub const Timing = extern struct {
    frame_count: u32,
    _unk_04: u32,
    total_time: f64,
    frame_time_64: f64,
    frame_time_64_raw: f64,
    frame_time: f32,
};
pub const TIMING: *Timing = @ptrCast(@alignCast(FRAMECOUNT));
pub const TIMING_SIZE: usize = @sizeOf(Timing);
// TODO: assert(TIMING_SIZE == 0x24);

pub const MFPS: *f32 = @ptrFromInt(0x4C8174); // sithControl_secFPS; fps/1000
pub const FPS: *f32 = @ptrFromInt(0x4C8178); // sithControl_msecFPS; actual fps

pub const FRAMETIME_MAX_CMP: *f64 = @ptrFromInt(0x4ADF88); // default: 0x3FB99999A0000000 (~0.100, 10fps)
pub const FRAMETIME_MAX1: *f32 = @ptrFromInt(0x4805A0 + 6); // x86 part
pub const FRAMETIME_MAX2: *f32 = @ptrFromInt(0x4805AA + 6); // x86 part
pub const FRAMETIME_MIN_CMP: *f64 = @ptrFromInt(0x4ADF70); // default: 0x0000000000000000 (~0.000)
pub const FRAMETIME_MIN1: *f32 = @ptrFromInt(0x480604 + 6); // x86 part; 0x3F60624DE0000001 (~0.002 or 500fps)
pub const FRAMETIME_MIN2: *f32 = @ptrFromInt(0x48060E + 6); // x86 part

// GUI

// HELPERS

// TODO: SetMinFrametime (that changes the instructions too), SetMaxFrametime, SetFixedFrametime
