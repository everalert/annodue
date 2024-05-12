pub const Self = @This();

// FIXME: convert ADDR naming to postfix

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
