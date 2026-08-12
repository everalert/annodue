// GAME FUNCTIONS

pub const GetTrackName: *fn (i32) callconv(.C) ?[*:0]const u8 = @ptrFromInt(0x440620);
// use with swrText_Translate

// GAME CONSTANTS

pub const CircuitSelectionTrackLUT: *[28]u8 = @ptrFromInt(0x4C0018);
pub const TrackMetadata: *[25]TRACK_METADATA = @ptrFromInt(0x4BFEE8);

// GAME DEFINITIONS

// FIXME: assert size
// len 0x0C
pub const TRACK_METADATA = extern struct {
    ModelBlockId: i32,
    SplineBlockId: i32,
    PlanetTrack: u8,
    Planet: u8,
    TrackFavorite: u8, // TODO: vehicle typedef
    _0B: u8, // TODO: unk
};

// HELPERS

pub const THE_BOONTA_TRAINING_COURSE = 0;
pub const THE_BOONTA_CLASSIC = 1;
pub const BEEDOS_WILD_RIDE = 2;
pub const HOWLER_GORGE = 3;
pub const ANDOBI_MOUNTAIN_RUN = 4;
pub const ANDO_PRIME_CENTRUM = 5;
pub const AQUILARIS_CLASSIC = 6;
pub const SUNKEN_CITY = 7;
pub const BUMPYS_BREAKERS = 8;
pub const SCRAPPERS_RUN = 9;
pub const DETHROS_REVENGE = 10;
pub const ABYSS = 11;
pub const BAROO_COAST = 12;
pub const GRABVINE_GATEWAY = 13;
pub const FIRE_MOUNTAIN_RALLY = 14;
pub const INFERNO = 15;
pub const MON_GAZZA_SPEEDWAY = 16;
pub const SPICE_MINE_RUN = 17;
pub const ZUGGA_CHALLENGE = 18;
pub const VENGEANCE = 19;
pub const EXECUTIONER = 20;
pub const THE_GAUNTLET = 21;
pub const MALASTARE_100 = 22;
pub const DUG_DERBY = 23;
pub const SEBULBAS_LEGACY = 24;

pub const AMATEUR_CIRCUIT = 0;
pub const SEMI_PRO_CIRCUIT = 1;
pub const GALACTIC_CIRCUIT = 2;
pub const INVITATIONAL_CIRCUIT = 3;

// FIXME: sentinel-terminated slice string type
// TODO: ?? deprecate, ingame function GetTrackName__440620 does this
/// track id -> track name
pub const TrackNameById = [25][*:0]const u8{
    "The Boonta Training Course",
    "The Boonta Classic",
    "Beedo's Wild Ride",
    "Howler Gorge",
    "Andobi Mountain Run",
    "Ando Prime Centrum",
    "Aquilaris Classic",
    "Sunken City",
    "Bumpy's Breakers",
    "Scrapper's Run",
    "Dethro's Revenge",
    "Abyss",
    "Baroo Coast",
    "Grabvine Gateway",
    "Fire Mountain Rally",
    "Inferno",
    "Mon Gazza Speedway",
    "Spice Mine Run",
    "Zugga Challenge",
    "Vengeance",
    "Executioner",
    "The Gauntlet",
    "Malastare 100",
    "Dug Derby",
    "Sebulba's Legacy",
};

// FIXME: sentinel-terminated slice string type
/// menu order id -> track name
pub const TrackNameByMenu: [25][*:0]const u8 = blk: {
    var map: [25][:0]const u8 = undefined;
    for (0..25) |i| map[i] = TrackNameById[TrackMenuIdMap[i]];
    break :blk map;
};

// TODO: ?? deprecate, ingame 0x4C0018 [28]i32 array is this map. kinda useful
//  to generate stuff w at comptime tho
/// menu order id -> track id
pub const TrackMenuIdMap: [25]u8 = .{
    0x00, 0x10, 0x02, 0x06, 0x16, 0x13, 0x11,
    0x07, 0x03, 0x17, 0x09, 0x12, 0x0C, 0x08,
    0x14, 0x18, 0x0D, 0x04, 0x0A, 0x0E, 0x01,
    0x05, 0x0B, 0x15, 0x0F,
};

/// track id -> menu order id
pub const TrackIdMenuMap: [25]u8 = blk: {
    var map: [25]u8 = undefined;
    for (0..25) |i| map[TrackMenuIdMap[i]] = i;
    break :blk map;
};

/// track id -> circuit id
pub const TrackCircuitIdMap = [_]u8{
    0, 2, 0, 1, 2, 3, 0, 1, 1, 1,
    2, 3, 1, 2, 2, 3, 0, 0, 1, 0,
    2, 3, 0, 1, 2,
};

/// track id -> nth track in circuit
pub const TrackCircuitNthTrackMap = [_]u8{
    0, 6, 2, 1, 3, 0, 3, 0, 6, 3,
    4, 1, 5, 2, 5, 3, 1, 6, 4, 5,
    0, 2, 4, 2, 1,
};
