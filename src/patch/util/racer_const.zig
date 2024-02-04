pub const Self = @This();

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
