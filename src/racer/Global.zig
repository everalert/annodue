const std = @import("std");
const w = std.os.windows;

// GAME FUNCTIONS

// ...

// GAME CONSTANTS

// Window

pub const HWND_ADDR: usize = 0x52EE70;
pub const HWND: *w.HWND = @ptrFromInt(HWND_ADDR);
pub const HINSTANCE_ADDR: usize = 0x52EE74;
pub const HINSTANCE: *w.HINSTANCE = @ptrFromInt(HINSTANCE_ADDR);

// Game State

pub const SCENE_ID_ADDR: usize = 0xE9BA62; // u16
pub const SCENE_ID: *u16 = @ptrFromInt(SCENE_ID_ADDR); // u16
pub const IN_RACE_ADDR: usize = 0xE9BB81; //u8
pub const IN_RACE: *u8 = @ptrFromInt(IN_RACE_ADDR); //u8
pub const IN_TOURNAMENT_ADDR: usize = 0x50C450; // u8
pub const IN_TOURNAMENT: *u8 = @ptrFromInt(IN_TOURNAMENT_ADDR); // u8

// Pausing

pub const PAUSE_STATE_ADDR: usize = 0x50C5F0; // u8
pub const PAUSE_STATE: *u8 = @ptrFromInt(PAUSE_STATE_ADDR);
pub const PAUSE_PAGE_ADDR: usize = 0x50C07C; // u8
pub const PAUSE_PAGE: *u8 = @ptrFromInt(PAUSE_PAGE_ADDR);
pub const PAUSE_SCROLLINOUT_ADDR: usize = 0xE9824C; // f32
pub const PAUSE_SCROLLINOUT: *f32 = @ptrFromInt(PAUSE_SCROLLINOUT_ADDR);

// GUI

// TODO: naming to something less ambiguous?

// TODO: try converting to bool
pub const GUI_STOPPED_ADDR: usize = 0x50CB64; // b32
pub const GUI_STOPPED: *u32 = @ptrFromInt(GUI_STOPPED_ADDR);

// HELPERS

// ...
