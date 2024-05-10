const std = @import("std");

// TODO: migrate all the old stuff from save editor, practice tool, notes, etc.

pub const MAGIC = [4]u8{ 0x03, 0x00, 0x01, 0x00 };

pub const Sav = extern struct {
    magic: [4]u8,
    data: Profile,
};

// TODO: testing to validate offsets
pub const Profile = extern struct {
    name: [0x20]u8,
    _unk_20_23: u32 = 0, //-> 0x20-0x23 = ??? (0x21 = 1?, 0x22 = file slot?, 0x23 = control related?)
    vehicle: u8,
    unlock_amateur: u8, // default 01
    unlock_semipro: u8, // default 01
    unlock_galactic: u8, // default 01
    unlock_invitational: u8, // default 00
    // _padding_29: u8,
    placement_amateur: u16,
    placement_semipro: u16,
    placement_galactic: u16,
    placement_invitational: u16,
    // _padding_32_33: u16,
    unlock_vehicles: u32, // default 0x012E0200
    truguts: i32,
    _unk_3C_3F: u32 = 0, //-> 0x3C-0x3F = ??? (0x3C has data)
    pitDroids: u8,
    upgrade_lv: [7]u8,
    upgrade_hp: [7]u8,
    // _padding_4F: u8,
};

pub const PROFILE_SIZE: usize = 0x50;

// TODO: testing to validate offsets
pub const Tgfd = extern struct {
    magic: [4]u8,

    _unk_004_017: [0x14]u8,
    //-> seems to have track/vehicle unlock stuff, maybe freeplay related

    profile: [4]Profile, //0x018 byte[4][0x50], file blocks

    //0x158 float[0x64], race times
    //-- default 3599.99 (0xD7FF6045) for no saved time
    //game ignores name and pod if time is default
    times: extern struct {
        lap3: [25]SavedTime,
        lap1: [25]SavedTime,
    },

    //0x2E8 string[0x64], time names
    //-- default AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA for no saved time, otherwise name padded with 0x00
    names: extern struct {
        lap3: [25]SavedName,
        lap1: [25]SavedName,
    },

    //0xF68 byte[0x64], time vehicles
    //-- defaults to track favourite for no saved time
    vehicles: extern struct {
        lap3: [25]SavedVehicle,
        lap1: [25]SavedVehicle,
    },

    _padding_FCC_FD7: [0xC]u8 = [_]u8{0} ** 0xC,
};

// default 3599.99 (0xD7FF6045) = blank time
pub const SavedTime = extern struct {
    normal: f32,
    mirror: f32,
};

// default AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA = blank time
pub const SavedName = extern struct {
    normal: [0x20]u8,
    mirror: [0x20]u8,
};

// default track favourite = blank time
pub const SavedVehicle = extern struct {
    normal: u8,
    mirror: u8,
};

pub const TGFD_SIZE: usize = 0x0FD8;
