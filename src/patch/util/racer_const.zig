pub const Self = @This();

// Window

pub const ADDR_HWND: usize = 0x52EE70;
pub const ADDR_HINSTANCE: usize = 0x52EE74;

// Magic words

pub const MAGIC_ABRT: u32 = 0x41627274; // Abrt
pub const MAGIC_RSTR: u32 = 0x52537472; // RStr
pub const MAGIC_FINI: u32 = 0x46696E69; // Fini

// Global State

pub const ADDR_SCENE_ID: usize = 0xE9BA62; // u16
pub const ADDR_IN_RACE: usize = 0xE9BB81; //u8
pub const ADDR_IN_TOURNAMENT: usize = 0x50C450; // u8

pub const ADDR_PAUSE_STATE: usize = 0x50C5F0; // u8
pub const ADDR_PAUSE_PAGE: usize = 0x50C07C; // u8
pub const ADDR_PAUSE_SCROLLINOUT: usize = 0xE9824C; // f32

pub const ADDR_TIME_TIMESTAMP: usize = 0x50CB60; // u32
pub const ADDR_TIME_FRAMETIME: usize = 0xE22A50; // f32
pub const ADDR_TIME_FRAMECOUNT: usize = 0xE22A30;
pub const ADDR_TIME_FPS: usize = 0x4C8174; // sithControl_secFPS

pub const ADDR_GUI_STOPPED: usize = 0x50CB64; // u32

// Entity System

pub const ADDR_ENTITY_MANAGER_JUMPTABLE: usize = 0x4BFEC0;
pub const ENTITY_MANAGER_SIZE: usize = 0x28;
pub const ENTITY = enum(u32) { Test = 0, Toss = 1, Trig = 2, Hang = 3, Jdge = 4, Scen = 5, Elmo = 6, Smok = 7, cMan = 8 };
pub const ENTITY_SIZE = [_]usize{ 0x1F28, 0x7C, 0x58, 0xD0, 0x1E8, 0x1B4C, 0xC0, 0x108, 0x3A8 };
pub fn EntitySize(entity: ENTITY) usize {
    return ENTITY_SIZE[@intFromEnum(entity)];
}

// Menu / 'Hang'

pub const ADDR_DRAW_MENU_JUMPTABLE: usize = 0x457A88;
pub const ADDR_DRAW_MENU_JUMPTABLE_SCENE_3: usize = 0x457AD4;

// Race Data (participant metadata)

pub const ADDR_RACE_DATA: usize = 0x4D78A4;
pub const RACE_DATA_SIZE: usize = 0x88;

// Input

// TODO: fix nomenclature to match game (Axis and Button)

pub const INPUT_ANALOG_LENGTH: usize = 4;
pub const INPUT_COMBINED_ANALOG_BASE_ADDR: usize = 0xEC8830;
pub const INPUT_JOYSTICK_ANALOG_BASE_ADDR: usize = 0x4D5E30;
pub const INPUT_MOUSE_ANALOG_BASE_ADDR: usize = 0x4D5E40;
pub const INPUT_KEYBOARD_ANALOG_BASE_ADDR: usize = 0x4D5E50;

pub const INPUT_DIGITAL_LENGTH: usize = 15;
pub const INPUT_COMBINED_DIGITAL_BASE_ADDR: usize = 0xEC8810;
pub const INPUT_JOYSTICK_DIGITAL_BASE_ADDR: usize = 0x4D5E80;
pub const INPUT_MOUSE_DIGITAL_BASE_ADDR: usize = 0x4D5EBC;
pub const INPUT_KEYBOARD_DIGITAL_BASE_ADDR: usize = 0x4D5EF8;

pub const INPUT_ANALOG = enum(u8) {
    Thrust,
    Unk2, // NOTE: not analog brake; that results in digital brake output
    Steering,
    Pitch,
};

pub const INPUT_ANALOG_STEERING: u8 = @intFromEnum(INPUT_ANALOG.Steering);
pub const INPUT_ANALOG_PITCH: u8 = @intFromEnum(INPUT_ANALOG.Pitch);

pub const INPUT_DIGITAL = enum(u8) {
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

pub const INPUT_DIGITAL_CAMERA: u8 = @intFromEnum(INPUT_DIGITAL.Camera);
pub const INPUT_DIGITAL_LOOK_BACK: u8 = @intFromEnum(INPUT_DIGITAL.LookBack);
pub const INPUT_DIGITAL_BRAKE: u8 = @intFromEnum(INPUT_DIGITAL.Brake);
pub const INPUT_DIGITAL_ACCELERATION: u8 = @intFromEnum(INPUT_DIGITAL.Acceleration);
pub const INPUT_DIGITAL_BOOST: u8 = @intFromEnum(INPUT_DIGITAL.Boost);
pub const INPUT_DIGITAL_SLIDE: u8 = @intFromEnum(INPUT_DIGITAL.Slide);
pub const INPUT_DIGITAL_ROLL_LEFT: u8 = @intFromEnum(INPUT_DIGITAL.RollLeft);
pub const INPUT_DIGITAL_ROLL_RIGHT: u8 = @intFromEnum(INPUT_DIGITAL.RollRight);
pub const INPUT_DIGITAL_TAUNT: u8 = @intFromEnum(INPUT_DIGITAL.Taunt);
pub const INPUT_DIGITAL_REPAIR: u8 = @intFromEnum(INPUT_DIGITAL.Repair);

// Text

pub const TEXT_COLOR_PRESET = [10]u32{
    0x000000, // (black)
    0xFFFFFF, // (white)
    0x6EB4FF, // (blue)
    0xFFFF9C, // (yellow)
    0x96FF96, // (green)
    0xFF6450, // (red)
    0xBC865E, // (brown)
    0x6E6E80, // (indigo-ish)
    0xFFA7D1, // (pink)
    0x985EFF, // (purple)
};

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

pub const TrackMenuIdMap = [_]u8{ 0x00, 0x10, 0x02, 0x06, 0x16, 0x13, 0x11, 0x07, 0x03, 0x17, 0x09, 0x12, 0x0C, 0x08, 0x14, 0x18, 0x0D, 0x04, 0x0A, 0x0E, 0x01, 0x05, 0x0B, 0x15, 0x0F };

pub const UpgradeCategories = [_][*:0]const u8{ "Traction", "Turning", "Acceleration", "Top Speed", "Air Brake", "Cooling", "Repair" };

pub const UpgradeNames = [_][*:0]const u8{ "R-20", "R-60", "R-80", "R-100", "R-300", "R-600", "Linkage", "Shift Plate", "Vectro-Jet", "Coupling", "Nozzle", "Stablizer", "Dual 20 PCX", "44 PCX", "Dual 32 PCX", "Quad 32 PCX", "Quad 44", "Mag 6", "Plug 2", "Plug 3", "Plug 5", "Plug 8", "Block 5", "Block 6", "Mark II", "Mark III", "Mark IV", "Mark V", "Tri-Jet", "Quadrijet", "Coolant", "Stack-3", "Stack-6", "Rod", "Dual", "Turbo", "Single", "Dual2", "Quad", "Cluster", "Rotary", "Cluster 2" };
