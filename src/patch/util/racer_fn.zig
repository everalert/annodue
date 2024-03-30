pub const Self = @This();

// Text

pub const swrText_CreateEntry: *fn (x: i16, y: i16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8, font: i32, entry2: u32) callconv(.C) void = @ptrFromInt(0x4503E0);

pub const swrText_CreateEntry1: *fn (x: i16, y: i16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x450530);

pub const swrText_CreateEntry2: *fn (x: i16, y: i16, r: u8, g: u8, b: u8, a: u8, str: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x4505C0);

pub const swrText_DrawTime2: *fn (x: i16, y: i16, time: f32, r: u8, g: u8, b: u8, a: u8, prefix: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x450670);

pub const swrText_DrawTime3: *fn (x: i16, y: i16, time: f32, r: u8, g: u8, b: u8, a: u8, prefix: [*:0]const u8) callconv(.C) void = @ptrFromInt(0x450760);

pub const swrText_NewNotification: *fn (str: [*:0]const u8, duration: f32) callconv(.C) void = @ptrFromInt(0x44FCE0);

// Quads

pub const swrQuad_InitQuad: *fn (i: u16, spr: u32) callconv(.C) void = @ptrFromInt(0x4282F0);

pub const swrQuad_LoadSprite: *fn (i: u32) callconv(.C) u32 = @ptrFromInt(0x446FB0);

pub const swrQuad_LoadTga: *fn (filename: [*:0]const u8, i: u32) callconv(.C) u32 = @ptrFromInt(0x4114D0);

pub const swrQuad_SetActive: *fn (i: u16, on: u32) callconv(.C) void = @ptrFromInt(0x4285D0);

pub const swrQuad_SetFlags: *fn (i: u16, flags: u32) callconv(.C) void = @ptrFromInt(0x4287E0);

pub const swrQuad_ClearFlagsExcept: *fn (i: u16, flags: u32) callconv(.C) void = @ptrFromInt(0x4287E0);

pub const swrQuad_SetPosition: *fn (i: u16, x: i16, y: i16) callconv(.C) void = @ptrFromInt(0x428660);

pub const swrQuad_SetScale: *fn (i: u16, w: f32, h: f32) callconv(.C) void = @ptrFromInt(0x4286F0);

pub const swrQuad_SetColor: *fn (i: u16, r: u8, g: u8, b: u8, a: u8) callconv(.C) void = @ptrFromInt(0x428740);

// Sound

pub const swrSound_PlayVoiceLine: *fn (type: i32, vehicle_id: i32, sound_id: i32, pos_vec3_ptr: u32) callconv(.C) void = @ptrFromInt(0x427410);

pub const swrSound_PlaySoundSpatial: *fn (id: i32, unk2: i32, pitch: f32, vol: f32, pos: usize, unk6: i32, unk7: i32, near: f32, far: f32) callconv(.C) void = @ptrFromInt(0x426D10);

pub const swrSound_PlaySound: *fn (id: i32, unk2: i32, pitch: f32, vol: f32, unk5: i32) callconv(.C) void = @ptrFromInt(0x426C80);

pub const swrSound_PlaySoundMacro: *fn (id: i32) callconv(.C) void = @ptrFromInt(0x440550);

// Input

pub const swrInput_ProcessInput: *fn () callconv(.C) void = @ptrFromInt(0x404DD0);

pub const swrInput_ReadControls: *fn () callconv(.C) void = @ptrFromInt(0x485630);

pub const swrInput_ReadKeyboard: *fn () callconv(.C) void = @ptrFromInt(0x486170);

pub const swrInput_ReadJoysticks: *fn () callconv(.C) void = @ptrFromInt(0x486340);

pub const swrInput_ReadMouse: *fn () callconv(.C) void = @ptrFromInt(0x486710);

// Loading

pub const TriggerLoad_InRace: *fn (jdge: usize, magic: u32) callconv(.C) void = @ptrFromInt(0x45D0B0);

// Camera

pub const swrCam_CamState_InitMainMat4: *fn (i: u16, val1: u16, mat4_ptr: usize, val2: u16) callconv(.C) void = @ptrFromInt(0x428A60);
