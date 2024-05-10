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

// Vehicle Metadata

// TODO: vehicle metadata struct def
pub const VEHICLE_METADATA_ARRAY_ADDR: usize = 0x4C2700;
pub const VEHICLE_METADATA_ITEM_SIZE: usize = 0x34;

// Input

pub const INPUT_RAW_STATE_TIMESTAMP: usize = 0x50E028;
pub const INPUT_RAW_STATE_ON: usize = 0x50E868;
pub const INPUT_RAW_STATE_JUST_ON: usize = 0x50F668;

pub const INPUT_COMBINED_ADDR: usize = 0xEC8810;
pub const INPUT_COMBINED_SIZE: usize = 0x30;

pub const INPUT_AXIS_LENGTH: usize = 4;
pub const INPUT_AXIS_SIZE: usize = INPUT_AXIS_LENGTH * 4;
pub const INPUT_AXIS_COMBINED_BASE_ADDR: usize = 0xEC8830;
pub const INPUT_AXIS_JOYSTICK_BASE_ADDR: usize = 0x4D5E30;
pub const INPUT_AXIS_MOUSE_BASE_ADDR: usize = 0x4D5E40;
pub const INPUT_AXIS_KEYBOARD_BASE_ADDR: usize = 0x4D5E50;

pub const INPUT_AXIS = enum(u8) {
    Thrust,
    Unk2, // NOTE: not analog brake; that results in digital brake output
    Steering,
    Pitch,
};
pub const INPUT_AXIS_STEERING: u8 = @intFromEnum(INPUT_AXIS.Steering);
pub const INPUT_AXIS_PITCH: u8 = @intFromEnum(INPUT_AXIS.Pitch);

pub const INPUT_BUTTON_LENGTH: usize = 15;
pub const INPUT_BUTTON_SIZE: usize = 16;
pub const INPUT_BUTTON_COMBINED_BASE_ADDR: usize = 0xEC8810;
pub const INPUT_BUTTON_JOYSTICK_BASE_ADDR: usize = 0x4D5E80;
pub const INPUT_BUTTON_MOUSE_BASE_ADDR: usize = 0x4D5EBC;
pub const INPUT_BUTTON_KEYBOARD_BASE_ADDR: usize = 0x4D5EF8;

pub const INPUT_BUTTON = enum(u8) {
    Camera,
    LookBack,
    Brake,
    Acceleration,
    Boost,
    Slide,
    RollLeft,
    RollRight,
    Taunt,
    Repair,
    Unk11,
    Unk12,
    Unk13,
    Unk14,
    Unk15,
};
pub const INPUT_BUTTON_CAMERA: u8 = @intFromEnum(INPUT_BUTTON.Camera);
pub const INPUT_BUTTON_LOOK_BACK: u8 = @intFromEnum(INPUT_BUTTON.LookBack);
pub const INPUT_BUTTON_BRAKE: u8 = @intFromEnum(INPUT_BUTTON.Brake);
pub const INPUT_BUTTON_ACCELERATION: u8 = @intFromEnum(INPUT_BUTTON.Acceleration);
pub const INPUT_BUTTON_BOOST: u8 = @intFromEnum(INPUT_BUTTON.Boost);
pub const INPUT_BUTTON_SLIDE: u8 = @intFromEnum(INPUT_BUTTON.Slide);
pub const INPUT_BUTTON_ROLL_LEFT: u8 = @intFromEnum(INPUT_BUTTON.RollLeft);
pub const INPUT_BUTTON_ROLL_RIGHT: u8 = @intFromEnum(INPUT_BUTTON.RollRight);
pub const INPUT_BUTTON_TAUNT: u8 = @intFromEnum(INPUT_BUTTON.Taunt);
pub const INPUT_BUTTON_REPAIR: u8 = @intFromEnum(INPUT_BUTTON.Repair);

// Text

pub const TEXT_COLOR_PRESET = [10]u32{
    0x000000, // (black)
    0xFFFFFF, // (white)
    0x6EB4FF, // (blue)
    0xFFFF9C, // (yellow)
    0x96FF96, // (green)
    0xFF6450, // (red)
    0xBC865E, // (brown)
    0x6E6E80, // (gray)
    0xFFA7D1, // (pink)
    0x985EFF, // (purple)
};

pub const TEXT_HIRES_FLAG: *u32 = @ptrFromInt(0x50C0AC);

// Quad (screenspace drawing)

pub const ADDR_QUAD_INITIALIZED_INDEX: usize = 0x4B91B8;
pub const ADDR_QUAD_STAT_BAR_INDEX: usize = 0x50C928;

// Camera

pub const CAM_METACAM_ARRAY_ADDR: usize = 0xDFB040; // NOTE: need a better name for this
pub const CAM_METACAM_ARRAY_LEN: usize = 4;
pub const CAM_METACAM_ITEM_SIZE: usize = 0x16C;

pub const CAM_CAMSTATE_ARRAY_ADDR: usize = 0xE9AA40;
pub const CAM_CAMSTATE_ARRAY_LEN: usize = 32;
pub const CAM_CAMSTATE_ITEM_SIZE: usize = 0x7C;

// Helper String Arrays

pub const Vehicles = [_][*:0]const u8{ "Anakin Skywalker", "Teemto Pagalies", "Sebulba", "Ratts Tyerell", "Aldar Beedo", "Mawhonic", "Ark 'Bumpy' Roose", "Wan Sandage", "Mars Guo", "Ebe Endocott", "Dud Bolt", "Gasgano", "Clegg Holdfast", "Elan Mak", "Neva Kee", "Bozzie Baranta", "Boles Roor", "Ody Mandrell", "Fud Sang", "Ben Quadinaros", "Slide Paramita", "Toy Dampner", "Bullseye 'Navior'" };

pub const TracksByMenu = [_][*:0]const u8{ "The Boonta Training Course", "Mon Gazza Speedway", "Beedo's Wild Ride", "Aquilaris Classic", "Malastare 100", "Vengeance", "Spice Mine Run", "Sunken City", "Howler Gorge", "Dug Derby", "Scrapper's Run", "Zugga Challenge", "Baroo Coast", "Bumpy's Breakers", "Executioner", "Sebulba's Legacy", "Grabvine Gateway", "Andobi Mountain Run", "Dethro's Revenge", "Fire Mountain Rally", "The Boonta Classic", "Ando Prime Centrum", "Abyss", "The Gauntlet", "Inferno" };

pub const TracksById = [_][*:0]const u8{ "The Boonta Training Course", "The Boonta Classic", "Beedo's Wild Ride", "Howler Gorge", "Andobi Mountain Run", "Ando Prime Centrum", "Aquilaris Classic", "Sunken City", "Bumpy's Breakers", "Scrapper's Run", "Dethro's Revenge", "Abyss", "Baroo Coast", "Grabvine Gateway", "Fire Mountain Rally", "Inferno", "Mon Gazza Speedway", "Spice Mine Run", "Zugga Challenge", "Vengeance", "Executioner", "The Gauntlet", "Malastare 100", "Dug Derby", "Sebulba's Legacy" };

// menu order idx -> track id
pub const TrackMenuIdMap = [_]u8{ 0x00, 0x10, 0x02, 0x06, 0x16, 0x13, 0x11, 0x07, 0x03, 0x17, 0x09, 0x12, 0x0C, 0x08, 0x14, 0x18, 0x0D, 0x04, 0x0A, 0x0E, 0x01, 0x05, 0x0B, 0x15, 0x0F };

// track id -> circuit id
pub const TrackCircuitIdMap = [_]u8{ 0, 2, 0, 1, 2, 3, 0, 1, 1, 1, 2, 3, 1, 2, 2, 3, 0, 0, 1, 0, 2, 3, 0, 1, 2 };

pub const UpgradeCategories = [_][*:0]const u8{ "Traction", "Turning", "Acceleration", "Top Speed", "Air Brake", "Cooling", "Repair" };

pub const UpgradeNames = [_][*:0]const u8{ "R-20", "R-60", "R-80", "R-100", "R-300", "R-600", "Linkage", "Shift Plate", "Vectro-Jet", "Coupling", "Nozzle", "Stablizer", "Dual 20 PCX", "44 PCX", "Dual 32 PCX", "Quad 32 PCX", "Quad 44", "Mag 6", "Plug 2", "Plug 3", "Plug 5", "Plug 8", "Block 5", "Block 6", "Mark II", "Mark III", "Mark IV", "Mark V", "Tri-Jet", "Quadrijet", "Coolant", "Stack-3", "Stack-6", "Rod", "Dual", "Turbo", "Single", "Dual2", "Quad", "Cluster", "Rotary", "Cluster 2" };
