pub const Test = @import("Test.zig");
pub const Toss = @import("Toss.zig");
pub const Trig = @import("Trig.zig");
pub const Hang = @import("Hang.zig");
pub const Jdge = @import("Jdge.zig");
pub const Scen = @import("Scen.zig");
pub const Elmo = @import("Elmo.zig");
pub const Smok = @import("Smok.zig");
pub const cMan = @import("cMan.zig");

// GAME FUNCTIONS

pub const CallFreeEvent: *fn (*anyopaque) callconv(.C) void = @ptrFromInt(0x450E30);

// GAME CONSTANTS

pub const MANAGER_JUMPTABLE_PTR_ADDR: usize = 0x4BFEC0;
pub const MANAGER_JUMPTABLE: *[*]*Manager = @ptrFromInt(MANAGER_JUMPTABLE_PTR_ADDR);
pub const MANAGER_SIZE: usize = 0x28;

// GAME TYPEDEFS

// MANAGER

// TODO: comptime generic that takes an actual entity id or something
// TODO: testing to assert the shape of the manager
pub const Manager = extern struct {
    magic: MAGIC_ENTITY,
    _unk_04: u32, // some kind of flags, maybe 2x u16
    count: u32,
    stride: u32,
    array: *align(4) anyopaque,
    fnStage14: *fn (entity: *align(4) anyopaque) callconv(.C) void,
    fnStage18: *fn (entity: *align(4) anyopaque) callconv(.C) void,
    fnStage1C: *fn (entity: *align(4) anyopaque) callconv(.C) void,
    fnStage20: *fn (entity: *align(4) anyopaque) callconv(.C) void,
    fnEvent: *fn (entity: *align(4) anyopaque, magic: [*]u32, payload: u32) callconv(.C) void,

    pub fn entity(comptime E: ENTITY, i: usize) *ENTITY.t(E) {
        const manager = MANAGER_JUMPTABLE.*[@intFromEnum(E)].*;
        return &@as([*]ENTITY.t(E), @ptrCast(manager.array))[i];
    }

    pub fn entitySlice(comptime E: ENTITY, i: usize) []u8 {
        const manager = MANAGER_JUMPTABLE.*[@intFromEnum(E)].*;
        const st = i * manager.stride;
        const en = st + manager.stride;
        return @as([*]u8, @ptrCast(manager.array))[st..en];
    }

    pub fn entitySliceAll(comptime E: ENTITY) []u8 {
        const manager = MANAGER_JUMPTABLE.*[@intFromEnum(E)].*;
        const len = manager.count * manager.stride;
        return @as([*]u8, @ptrCast(manager.array))[0..len];
    }
};

// ENTITY TYPES

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

    pub inline fn t(comptime E: ENTITY) type {
        return switch (E) {
            .Test => Test.Test,
            .Toss => Toss.Toss,
            .Trig => Trig.Trig,
            .Hang => Hang.Hang,
            .Jdge => Jdge.Jdge,
            .Scen => Scen.Scen,
            .Elmo => Elmo.Elmo,
            .Smok => Smok.Smok,
            .cMan => cMan.cMan,
        };
    }
};

pub const ENTITY_SIZE = [_]usize{
    0x1F28,
    0x7C,
    0x58,
    0xD0,
    0x1E8,
    0x1B4C,
    0xC0,
    0x108,
    0x3A8,
};

pub inline fn EntitySize(entity: ENTITY) usize {
    return ENTITY_SIZE[@intFromEnum(entity)];
}

pub const MAGIC_ENTITY = enum(u32) {
    Test = 0x54657374,
    Toss = 0x546F7373,
    Trig = 0x54726967,
    Hang = 0x48616E67,
    Jdge = 0x4A646765,
    Scen = 0x5363656E,
    Elmo = 0x456C6D6F,
    Smok = 0x536D6F6B,
    cMan = 0x634D616E,
    //Chsr = 0x43687372,
};

pub const M_TEST: u32 = @intFromEnum(MAGIC_ENTITY.Test);
pub const M_TOSS: u32 = @intFromEnum(MAGIC_ENTITY.Toss);
pub const M_TRIG: u32 = @intFromEnum(MAGIC_ENTITY.Trig);
pub const M_HANG: u32 = @intFromEnum(MAGIC_ENTITY.Hang);
pub const M_JDGE: u32 = @intFromEnum(MAGIC_ENTITY.Jdge);
pub const M_SCEN: u32 = @intFromEnum(MAGIC_ENTITY.Scen);
pub const M_ELMO: u32 = @intFromEnum(MAGIC_ENTITY.Elmo);
pub const M_SMOK: u32 = @intFromEnum(MAGIC_ENTITY.Smok);
pub const M_CMAN: u32 = @intFromEnum(MAGIC_ENTITY.cMan);
//pub const M_CHSR: u32 = @intFromEnum(MAGIC_ENTITY.Chsr);

// EVENT TYPES

pub const MAGIC_EVENT = enum(u32) {
    Paws = 0x50617773,
    Load = 0x4C6F6164,
    Free = 0x46726565,
    Stop = 0x53746F70,
    Slep = 0x536C6570,
    Wake = 0x57616B65,
    RSet = 0x52536574,
    Abrt = 0x41627274,
    // Jdge
    RStr = 0x52537472,
    Fini = 0x46696E69,
    JAsn = 0x4A41736E,
    NAsn = 0x4E41736E,
    Begn = 0x4265676E,
    Join = 0x4A6F696E,
    Mstr = 0x4D737472,
};

pub const M_ABRT: u32 = @intFromEnum(MAGIC_EVENT.Abrt);
pub const M_RSTR: u32 = @intFromEnum(MAGIC_EVENT.RStr);
pub const M_FINI: u32 = @intFromEnum(MAGIC_EVENT.Fini);

// HELPERS

// ...
