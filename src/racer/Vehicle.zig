// GAME FUNCTIONS

pub const Vehicle_EnableJinnReeso: *fn () callconv(.C) void = @ptrFromInt(0x44B530);
pub const Vehicle_EnableCyYunga: *fn () callconv(.C) void = @ptrFromInt(0x44B5E0);

// GAME CONSTANTS

// TODO: vehicle metadata struct def
pub const METADATA_ARRAY_ADDR: usize = 0x4C2700;
pub const METADATA_ITEM_SIZE: usize = 0x34;

// TODO: figure out what the mystery struct is
pub const MYSTERY_ARRAY_ADDR: usize = 0x4C7088;
pub const MYSTERY_ITEM_SIZE: usize = 0x6C;

pub const JINN_REESO_METADATA_ADDR: usize = METADATA_ARRAY_ADDR + METADATA_ITEM_SIZE * 8;
pub const JINN_REESO_MYSTERY_ADDR: usize = MYSTERY_ARRAY_ADDR + MYSTERY_ITEM_SIZE * 8;

pub const CY_YUNGA_METADATA_ADDR: usize = METADATA_ARRAY_ADDR + METADATA_ITEM_SIZE * 22;
pub const CY_YUNGA_MYSTERY_ADDR: usize = MYSTERY_ARRAY_ADDR + MYSTERY_ITEM_SIZE * 22;

// HELPERS

pub const VehicleNames = [_][*:0]const u8{
    "Anakin Skywalker",
    "Teemto Pagalies",
    "Sebulba",
    "Ratts Tyerell",
    "Aldar Beedo",
    "Mawhonic",
    "Ark 'Bumpy' Roose",
    "Wan Sandage",
    "Mars Guo",
    "Ebe Endocott",
    "Dud Bolt",
    "Gasgano",
    "Clegg Holdfast",
    "Elan Mak",
    "Neva Kee",
    "Bozzie Baranta",
    "Boles Roor",
    "Ody Mandrell",
    "Fud Sang",
    "Ben Quadinaros",
    "Slide Paramita",
    "Toy Dampner",
    "Bullseye 'Navior'",
};

// TODO: move upgrades/parts stuff to Stats.zig?
pub const UpgradeNames = [_][*:0]const u8{
    "Traction",
    "Turning",
    "Acceleration",
    "Top Speed",
    "Air Brake",
    "Cooling",
    "Repair",
};

pub inline fn PartNameS(upgradeId: usize) []const [*:0]const u8 {
    return PartNamesShort[upgradeId * 6 .. upgradeId * 6 + 6];
}

// TODO: full names
pub const PartNamesShort = [_][*:0]const u8{
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
