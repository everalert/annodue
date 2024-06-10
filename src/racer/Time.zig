// TODO: confirm b32 stuff works with bool def

// GAME FUNCTIONS

pub const Time_Tick: *fn () callconv(.C) void = @ptrFromInt(0x480540);
pub const Time_SetFixedFrametime: *fn (frametime: f64) callconv(.C) void = @ptrFromInt(0x480480);
pub const Time_SetStopped: *fn (stopped: bool) callconv(.C) void = @ptrFromInt(0x4804B0); // b32

// GAME CONSTANTS

pub const TIMESTAMP_ADDR: usize = 0x50CB60;
pub const TIMESTAMP: *u32 = @ptrFromInt(TIMESTAMP_ADDR);
pub const STOPPED_ADDR: usize = 0x50CB64; // b32
pub const STOPPED: *bool = @ptrFromInt(STOPPED_ADDR);
pub const FIXED_STEP_ON_ADDR: usize = 0x50CB68; // b32
pub const FIXED_STEP_ON: *bool = @ptrFromInt(FIXED_STEP_ON_ADDR);
pub const FIXED_FRAMETIME_ADDR: usize = 0x50CB70;
pub const FIXED_FRAMETIME: *f64 = @ptrFromInt(FIXED_FRAMETIME_ADDR);

// TODO: typedef of struct holding this info, then update dll_savestate with new refs

pub const FRAMECOUNT_ADDR: usize = 0xE22A30;
pub const FRAMECOUNT: *u32 = @ptrFromInt(FRAMECOUNT_ADDR);
pub const TOTALTIME_ADDR: usize = 0xE22A38;
pub const TOTALTIME: *f64 = @ptrFromInt(TOTALTIME_ADDR);
pub const FRAMETIME_64_ADDR: usize = 0xE22A40;
pub const FRAMETIME_64: *f64 = @ptrFromInt(FRAMETIME_64_ADDR);
pub const FRAMETIME_64_RAW_ADDR: usize = 0xE22A48;
pub const FRAMETIME_64_RAW: *f64 = @ptrFromInt(FRAMETIME_64_RAW_ADDR);
pub const FRAMETIME_ADDR: usize = 0xE22A50;
pub const FRAMETIME: *f32 = @ptrFromInt(FRAMETIME_ADDR);

pub const MFPS_ADDR: usize = 0x4C8174; // sithControl_secFPS; fps/1000
pub const MFPS: *f32 = @ptrFromInt(MFPS_ADDR);
pub const FPS_ADDR: usize = 0x4C8178; // sithControl_msecFPS; actual fps
pub const FPS: *f32 = @ptrFromInt(FPS_ADDR);

pub const FRAMETIME_MAX_CMP_ADDR: usize = 0x4ADF88; // default: 0x3FB99999A0000000 (~0.100, 10fps)
pub const FRAMETIME_MAX_CMP: *f64 = @ptrFromInt(FRAMETIME_MAX_CMP_ADDR);
pub const FRAMETIME_MAX1_ADDR: usize = 0x4805A0 + 6; // instruction part
pub const FRAMETIME_MAX1: *f32 = @ptrFromInt(FRAMETIME_MAX1_ADDR);
pub const FRAMETIME_MAX2_ADDR: usize = 0x4805AA + 6; // instruction part
pub const FRAMETIME_MAX2: *f32 = @ptrFromInt(FRAMETIME_MAX2_ADDR);
pub const FRAMETIME_MIN_CMP_ADDR: usize = 0x4ADF70; // default: 0x0000000000000000 (~0.000)
pub const FRAMETIME_MIN_CMP: *f64 = @ptrFromInt(FRAMETIME_MIN_CMP_ADDR);
pub const FRAMETIME_MIN1_ADDR: usize = 0x480604 + 6; // instruction part; 0x3F60624DE0000001 (~0.002 or 500fps)
pub const FRAMETIME_MIN1: *f32 = @ptrFromInt(FRAMETIME_MIN1_ADDR);
pub const FRAMETIME_MIN2_ADDR: usize = 0x48060E + 6; // instruction part
pub const FRAMETIME_MIN2: *f32 = @ptrFromInt(FRAMETIME_MIN2_ADDR);

// GUI

// HELPERS

// TODO: SetMinFrametime (that changes the instructions too), SetMaxFrametime, SetFixedFrametime
