pub const Self = @This();

// Sound

pub const swrSound_PlayVoiceLine: *fn (type: i32, vehicle_id: i32, sound_id: i32, pos_vec3_ptr: u32) callconv(.C) void = @ptrFromInt(0x427410);
pub const swrSound_PlaySoundSpatial: *fn (id: i32, unk2: i32, pitch: f32, vol: f32, pos: usize, unk6: i32, unk7: i32, near: f32, far: f32) callconv(.C) void = @ptrFromInt(0x426D10);
pub const swrSound_PlaySound: *fn (id: i32, unk2: i32, pitch: f32, vol: f32, unk5: i32) callconv(.C) void = @ptrFromInt(0x426C80);
pub const swrSound_PlaySoundMacro: *fn (id: i32) callconv(.C) void = @ptrFromInt(0x440550);

// Video

// NOTE: strings found at 0x4B7A44 in game memory
/// @filename   a .znm file located in /data/anims
pub const swrVideo_PlayVideoFile: *fn (filename: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x4252A0);

// Loading

pub const TriggerLoad_InRace: *fn (jdge: *anyopaque, magic: u32) callconv(.C) void = @ptrFromInt(0x45D0B0);

// Camera

pub const swrCam_CamState_InitMainMat4: *fn (i: u16, val1: u16, mat4_ptr: usize, val2: u16) callconv(.C) void = @ptrFromInt(0x428A60);

// Vehicle Metadata

pub const Vehicle_EnableJinnReeso: *fn () callconv(.C) void = @ptrFromInt(0x44B530);
pub const Vehicle_EnableCyYunga: *fn () callconv(.C) void = @ptrFromInt(0x44B5E0);
