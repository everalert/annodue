pub const Self = @This();

// FIXME: convert ADDR naming to postfix

// Window

pub const ADDR_HWND: usize = 0x52EE70;
pub const ADDR_HINSTANCE: usize = 0x52EE74;

// Global State

pub const ADDR_SCENE_ID: usize = 0xE9BA62; // u16
pub const ADDR_IN_RACE: usize = 0xE9BB81; //u8
pub const ADDR_IN_TOURNAMENT: usize = 0x50C450; // u8

pub const ADDR_PAUSE_STATE: usize = 0x50C5F0; // u8
pub const ADDR_PAUSE_PAGE: usize = 0x50C07C; // u8
pub const ADDR_PAUSE_SCROLLINOUT: usize = 0xE9824C; // f32
pub const PAUSE_STATE: *u8 = @ptrFromInt(0x50C5F0);
pub const PAUSE_PAGE: *u8 = @ptrFromInt(0x50C07C);
pub const PAUSE_SCROLLINOUT: *f32 = @ptrFromInt(0xE9824C);

pub const ADDR_TIME_TIMESTAMP: usize = 0x50CB60; // u32
pub const ADDR_TIME_FRAMETIME: usize = 0xE22A50; // f32
pub const ADDR_TIME_FRAMETIME_64: usize = 0xE22A40; // f64
pub const ADDR_TIME_FRAMECOUNT: usize = 0xE22A30;
pub const ADDR_TIME_FPS: usize = 0x4C8174; // sithControl_secFPS
pub const TIME_TIMESTAMP: *u32 = @ptrFromInt(0x50CB60);
pub const TIME_FRAMETIME: *f32 = @ptrFromInt(0xE22A50);
pub const TIME_FRAMETIME_64: *f64 = @ptrFromInt(0xE22A40);
pub const TIME_FRAMECOUNT: *u32 = @ptrFromInt(0xE22A30);

pub const ADDR_GUI_STOPPED: usize = 0x50CB64; // u32

// Camera

pub const CAM_METACAM_ARRAY_ADDR: usize = 0xDFB040; // NOTE: need a better name for this
pub const CAM_METACAM_ARRAY_LEN: usize = 4;
pub const CAM_METACAM_ITEM_SIZE: usize = 0x16C;

pub const CAM_CAMSTATE_ARRAY_ADDR: usize = 0xE9AA40;
pub const CAM_CAMSTATE_ARRAY_LEN: usize = 32;
pub const CAM_CAMSTATE_ITEM_SIZE: usize = 0x7C;

// Helper String Arrays

pub const TracksByMenu = [_][*:0]const u8{ "The Boonta Training Course", "Mon Gazza Speedway", "Beedo's Wild Ride", "Aquilaris Classic", "Malastare 100", "Vengeance", "Spice Mine Run", "Sunken City", "Howler Gorge", "Dug Derby", "Scrapper's Run", "Zugga Challenge", "Baroo Coast", "Bumpy's Breakers", "Executioner", "Sebulba's Legacy", "Grabvine Gateway", "Andobi Mountain Run", "Dethro's Revenge", "Fire Mountain Rally", "The Boonta Classic", "Ando Prime Centrum", "Abyss", "The Gauntlet", "Inferno" };

pub const TracksById = [_][*:0]const u8{ "The Boonta Training Course", "The Boonta Classic", "Beedo's Wild Ride", "Howler Gorge", "Andobi Mountain Run", "Ando Prime Centrum", "Aquilaris Classic", "Sunken City", "Bumpy's Breakers", "Scrapper's Run", "Dethro's Revenge", "Abyss", "Baroo Coast", "Grabvine Gateway", "Fire Mountain Rally", "Inferno", "Mon Gazza Speedway", "Spice Mine Run", "Zugga Challenge", "Vengeance", "Executioner", "The Gauntlet", "Malastare 100", "Dug Derby", "Sebulba's Legacy" };

// menu order idx -> track id
pub const TrackMenuIdMap = [_]u8{ 0x00, 0x10, 0x02, 0x06, 0x16, 0x13, 0x11, 0x07, 0x03, 0x17, 0x09, 0x12, 0x0C, 0x08, 0x14, 0x18, 0x0D, 0x04, 0x0A, 0x0E, 0x01, 0x05, 0x0B, 0x15, 0x0F };

// track id -> circuit id
pub const TrackCircuitIdMap = [_]u8{ 0, 2, 0, 1, 2, 3, 0, 1, 1, 1, 2, 3, 1, 2, 2, 3, 0, 0, 1, 0, 2, 3, 0, 1, 2 };
