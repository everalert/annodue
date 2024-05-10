const std = @import("std");
const f = @import("File.zig");

pub const SIZE: usize = 0x88;

pub const PLAYER_PTR_ADDR: usize = 0x4D78A4;
pub const PLAYER_PTR: *usize = @ptrFromInt(PLAYER_PTR_ADDR);
// TODO: double pointer; original data probably game state struct holding the ptr
pub const PLAYER: **RaceData = @ptrFromInt(PLAYER_PTR_ADDR);
pub const PLAYER_SLICE: **[SIZE]u8 = @ptrFromInt(PLAYER_PTR_ADDR);

// TODO: confirm static
pub const ARRAY_ADDR: usize = 0xE29BC0;
pub const ARRAY: *[12]RaceData = @ptrFromInt(ARRAY_ADDR);
pub const SLICE_ARRAY: *[12][SIZE]u8 = @ptrFromInt(ARRAY_ADDR);

pub const RaceData = extern struct {
    index: u32,
    control: u32,
    flags: u32, // TODO: enum
    pFile: *f.Profile, // ptr to profile? file data in memory
    unk10: u32,
    unk14: u32,
    pVehicleMetadata: u32,
    stats: [15]f32, // TODO: stats struct
    unk58: u32,
    pos: u32,
    time: extern struct {
        lap: [5]f32,
        total: f32,
    },
    lap: u32,
    unk7C: u32,
    unk80: u32, // post-race part damage factor?
    pTestEntity: u32, // TODO: test entity struct
};

pub const RaceDataOffset = enum(u32) {
    index = 0x00,
    control = 0x04,
    flags = 0x08,
    pFile = 0x0C,
    unk10 = 0x10,
    unk14 = 0x14,
    pVehicleMetadata = 0x18,
    stats = 0x1C,
    unk58 = 0x58,
    pos = 0x5C,
    lapTime1 = 0x60,
    lapTime2 = 0x64,
    lapTime3 = 0x68,
    lapTime4 = 0x6C,
    lapTime5 = 0x70,
    totalTime = 0x74,
    lap = 0x78,
    unk7C = 0x7C,
    unk80 = 0x80,
    pTestEntity = 0x84,

    pub fn v(self: *const RaceDataOffset) u32 {
        return @intFromEnum(self.*);
    }
};
