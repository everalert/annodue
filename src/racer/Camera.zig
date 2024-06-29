// GAME FUNCTIONS

pub const swrCam_CamState_InitMainMat4: *fn (i: u16, val1: u16, mat4_ptr: usize, val2: u16) callconv(.C) void = @ptrFromInt(0x428A60);

// GAME CONSTANTS

// TODO: typedef
// TODO: need a better name for this
pub const METACAM_ARRAY_ADDR: usize = 0xDFB040;
pub const METACAM_ARRAY_LEN: usize = 4;
pub const METACAM_ITEM_SIZE: usize = 0x16C;

// TODO: typedef
pub const CAMSTATE_ARRAY_ADDR: usize = 0xE9AA40;
pub const CAMSTATE_ARRAY_LEN: usize = 32;
pub const CAMSTATE_ITEM_SIZE: usize = 0x7C;

// GAME TYPEDEFS

// ...

// HELPERS

// ...
