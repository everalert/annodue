pub const Self = @This();

// Window

pub const ADDR_HWND: usize = 0x52EE70;
pub const ADDR_HINSTANCE: usize = 0x52EE74;

// Magic words

pub const MAGIC_ABRT: u32 = 0x41627274; // Abrt
pub const MAGIC_RSTR: u32 = 0x52537472; // RStr
pub const MAGIC_FINI: u32 = 0x46696E69; // Fini

// Entity System
pub const ADDR_ENTITY_MANAGER_JUMP_TABLE: usize = 0x4BFEC0;
pub const ENTITY_MANAGER_SIZE: usize = 0x28;
pub const ENTITY = enum(u32) {
    Test = 0,
    Toss = 1,
    Trig = 2,
    Hang = 3,
    Jdge = 4,
    Scen = 5,
    Elmo = 6,
    Smok = 7,
    cMan = 8,
};

// Global State
pub const ADDR_SCENE_ID: usize = 0xE9BA62; // u16
pub const ADDR_IN_RACE: usize = 0xE9BB81; //u8
pub const ADDR_IN_TOURNAMENT: usize = 0x50C450; // u8
pub const ADDR_PAUSE_STATE: usize = 0x50C5F0; // u8

// Menu / 'Hang'
pub const ADDR_DRAW_MENU_JUMP_TABLE: usize = 0x457A88;
pub const ADDR_DRAW_MENU_JUMP_TABLE_SCENE_3: usize = 0x457AD4;

// Helper Strings
pub const UpgradeCategories = [_][*:0]const u8{
    "Traction",
    "Turning",
    "Acceleration",
    "Top Speed",
    "Air Brake",
    "Cooling",
    "Repair",
};

pub const UpgradeNames = [_][*:0]const u8{
    "R-20",
    "R-60",
    "R-80",
    "R-100",
    "R-300",
    "R-600",
    "Linkage",
    "Shift Plate",
    "Vectro-Jet",
    "Coupling",
    "Nozzle",
    "Stablizer",
    "Dual 20 PCX",
    "44 PCX",
    "Dual 32 PCX",
    "Quad 32 PCX",
    "Quad 44",
    "Mag 6",
    "Plug 2",
    "Plug 3",
    "Plug 5",
    "Plug 8",
    "Block 5",
    "Block 6",
    "Mark II",
    "Mark III",
    "Mark IV",
    "Mark V",
    "Tri-Jet",
    "Quadrijet",
    "Coolant",
    "Stack-3",
    "Stack-6",
    "Rod",
    "Dual",
    "Turbo",
    "Single",
    "Dual2",
    "Quad",
    "Cluster",
    "Rotary",
    "Cluster 2",
};
