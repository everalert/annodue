const std = @import("std");

const lib_track = @import("Track.zig");

// GAME FUNCTIONS

// void __cdecl Save_InitProfileData_43EA00(BOOL TGFD, int Slot)
// void __stdcall MassGenerateDefaultDataSAV_maybe_43D970()
// void __cdecl Unk_Save_GenerateDefaultGameSave__44E320(SAVE_TGFD *out_pTgfd)
// void Unk_Save_TgfdRelated__44E4E0() // NOTE: copies local tgfd to unk local tgfd
// void __cdecl Unk_Save_InitMainProfile__421AC0(const char *pFilename)
// void __cdecl Unk_Save_CopyProfileToGameSaveSlot__44E530(int to_GameSaveProfileSlot, int from_ProfileSlot)
// void __cdecl Unk_Save_ResetGameSave__421B20(BOOL bClearLoadedProfile)
// BOOL Unk_Save_AreFreePlayVehiclesCleared__421D80()
// void __cdecl Unk_Save_CopyProfileFromGameSaveSlot__44E500(int to_ProfileSlot, int from_GameSaveProfileSlot)
// BOOL __cdecl Unk_Save_ProfileFileRead__421850(const char *pFilename)
// void __cdecl Unk_Save_ProfileFileDelete__421950(const char *pFilename)
// BOOL __cdecl Unk_Save_ProfileFileWrite__4219D0(const char *pFilename)
// BOOL Unk_Save_GameSaveFileWrite__421C90()
// BOOL Unk_Save_GameSaveFileRead__421B90()
// void __stdcall Unk_Save_WriteAll__44E560()

// GAME CONSTANTS

pub const ProfileData: *[20]SAVE_PROFILE = @ptrFromInt(0xE35A60);
pub const GameSaveData: *SAVE_GAME = @ptrFromInt(0xE364A0);
pub const UnkGameSaveData: *SAVE_GAME = @ptrFromInt(0xE34A80); // TODO: look into semantics, not the 'main' tgfd

pub const GameSaveFilename: [*:0]const u8 = @ptrFromInt(0x4B6D00); // tgfd.dat

// GAME DEFINITIONS

pub const SAVE_MAGIC: u32 = 0x00010003;

pub const BestTimeDefaultTime: f32 = 3599.99; // 0xD7FF6045; 59:59.990
pub const BestTimeDefaultName: [31:0]u8 = undefined; // fills with A in zig, which matches racer default name

// FIXME: assert size
// len 0x50
// .sav file
pub const SAVE_PROFILE = extern struct {
    Filename: [31:0]u8,
    _20: u8,
    _21: u8,
    FileSlot: u8,
    _23_unk_ctrl: u8,
    SelectedVehicle: u8,
    CircuitTracks: [4]u8, // TODO: circuit typedefs
    _29: u8,
    CircuitPlacements: [4]u16, // TODO: circuit typedefs
    _32: u8,
    _33: u8,
    VehicleUnlocks: u32, // TODO: vehicles typedef, enum
    Truguts: i32,
    _3C: u8,
    _3D: u8,
    _3E: u8,
    _3F: u8,
    PitDroids: u8,
    UpgradeLevels: [7]u8,
    UpgradeHealths: [7]u8,
    _4F: u8,
};

// FIXME: assert size
// len 0xFD4
// tgfd.dat file
pub const SAVE_GAME = extern struct {
    _000_003: [4]u8,
    _004: u8,
    _005: u8,
    _006: u8,
    _007: u8,
    _008: u8,
    _009_00B: [3]u8,
    FreePlayTracks: [4]u8, // TODO: circuit typedefs (same as SAVE_SAV)
    FreePlayVehicles: u32, // TODO: vehicles typedef, enum (same as SAVE_SAV)
    ProfileSaves: [4]SAVE_PROFILE,
    BestTimeTimes: [100]f32,
    BestTimeNames: [100][31:0]u8,
    BestTimeVehicles: [100]u8, // TODO: vehicles enum
};

// HELPERS

// FIXME: argument/return typing
pub fn BestTimeIndex(track: u32, laps: u32, mirror_mode: bool) u32 {
    std.debug.assert(track < 25);
    std.debug.assert(laps == 1 or laps == 3);
    return 50 * @as(u32, @intFromBool(laps == 1)) + 2 * track + @intFromBool(mirror_mode);
}

pub fn BestTimeSet(save: *SAVE_GAME, track: u32, laps: u32, mirror_mode: bool, time: ?f32, name: ?[*:0]const u8, vehicle: ?u32) void {
    if (time) |t| std.debug.assert(t > 0 and t < BestTimeDefaultTime);
    if (name) |n| std.debug.assert(std.mem.len(n) < 32);
    if (vehicle) |v| std.debug.assert(v < 23);
    const index: u32 = BestTimeIndex(track, laps, mirror_mode);
    save.BestTimeTimes[index] = time orelse BestTimeDefaultTime;
    save.BestTimeVehicles[index] = @intCast(vehicle orelse lib_track.TrackMetadata[track].TrackFavorite);
    if (name) |n| {
        save.BestTimeNames[index] = std.mem.zeroes([31:0]u8);
        _ = std.fmt.bufPrintZ(&save.BestTimeNames[index], "{s}", .{n}) catch unreachable; // name len checked
    } else {
        save.BestTimeNames[index] = BestTimeDefaultName;
    }
}

pub fn BestTimeClear(save: *SAVE_GAME, track: u32, laps: u32, mirror_mode: bool) void {
    BestTimeSet(save, track, laps, mirror_mode, null, null, null);
}
