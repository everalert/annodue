const std = @import("std");
const EnumSet = std.EnumSet;
const w = std.os.windows;
const BOOL = w.BOOL;

const e = @import("entity.zig");

// GAME FUNCTIONS

// called with fn(hang,1,0) in cb0x14
// arg3 probably also BOOL
pub const LoadRace: *fn (hang: *Hang, unk2: BOOL, unk3: u32) callconv(.C) void = @ptrFromInt(0x457410);
pub const LoadRaceMacro: *fn (hang: *Hang) callconv(.C) void = @ptrFromInt(0x434EA0);

pub const fnStage14: *fn (hang: *Hang) callconv(.C) void = @ptrFromInt(0x457620);
//pub const fnStage18: *fn (hang: *Hang) callconv(.C) void = @ptrFromInt(0x00);
pub const fnStage1C: *fn (hang: *Hang) callconv(.C) void = @ptrFromInt(0x457B00);
pub const fnStage20: *fn (hang: *Hang) callconv(.C) void = @ptrFromInt(0x457B90);
pub const fnEvent: *fn (hang: *Hang, magic: *e.MAGIC_EVENT, payload: u32) callconv(.C) void = @ptrFromInt(0x45A040);

// GAME CONSTANTS

pub const DRAW_MENU_JUMPTABLE_ADDR: usize = 0x457A88;
pub const DRAW_MENU_JUMPTABLE_SCENE_3_ADDR: usize = 0x457AD4;

// GAME TYPEDEFS

pub const SIZE: usize = e.EntitySize(.Hang);

// TODO: testing assertion of size correctness
pub const Hang = extern struct {
    EntityMagic: u32,
    EntityFlags: u32,
    MenuScreen: HangMenuScreen,
    MenuScreenPrev: HangMenuScreen,
    ActiveMenu: i32,
    Flags: u32, // ideally EnumSet(HangFlags), but cannot include in extern struct def
    _unk_18: u32,
    _unk_1C: u32,
    pModelHangar: *anyopaque, // FIXME: typedef, swrModel_unk on swe1r_re
    pModelCantina: *anyopaque, // FIXME: typedef, swrModel_unk on swe1r_re
    pModelCounter: *anyopaque, // FIXME: typedef, swrModel_unk on swe1r_re
    pModelJunkyard: *anyopaque, // FIXME: typedef, swrModel_unk on swe1r_re
    pModelHolotable: *anyopaque, // FIXME: typedef, swrModel_unk on swe1r_re
    CameraState: HangCameraState,
    Room: HangRoom, // the physical space
    RoomPrev: HangRoom,
    ElmoEntityIndex: i32,
    ElmoFocusPosition: [3]f32, // FIXME: vec3 typedef
    _unk_50: i8, // index to unknown Elmo-related vec3 array
    ShowDeveloperPhoto: i8, // BOOL
    _unk_52: u8, // possibly unused
    _unk_53: u8, // possibly unused
    _unk_54: u32,
    _unk_58: u32,
    _unk_5C: u8,
    Track: u8, // 0x5D
    Circuit: u8,
    MainMenuSelection: u8,
    _unk_60: u32, // possibly low byte only
    _unk_64: u32,
    _unk_68: u32, // run on menu screen "legal"
    TournamentMode: i8, // BOOL
    TimeAttackMode: i8, // BOOL
    Mirror: i8, // BOOL
    PlayerIndex: u8,
    PlayerCount: u8,
    _unk_71: u8,
    Racers: u8,
    VehiclePlayer: u8, // FIXME: should be merged with VehicleOpponent but zig complains about alignment; 0x73
    VehicleOpponent: [22]u8,
    _unk_8A: u8,
    _unk_8B: u8, // possibly unused
    _unk_8C: u8, // possibly unused
    _unk_8D: u8, // possibly unused
    _unk_8E: u8, // possibly unused
    Laps: i8,
    AISpeed: i8,
    Winnings: i8,
    PrizeFair1: i16, // TODO: impl payout struct
    PrizeFair2: i16,
    PrizeFair3: i16,
    PrizeFair4: i16,
    PrizeSkilled1: i16,
    PrizeSkilled2: i16,
    PrizeSkilled3: i16,
    PrizeSkilled4: i16,
    PrizeWinnerTakesAll1: i16,
    PrizeWinnerTakesAll2: i16,
    PrizeWinnerTakesAll3: i16,
    PrizeWinnerTakesAll4: i16,
    _unk_AA: u8, // possibly unused
    _unk_AB: u8, // possibly unused
    _unk_AC: u32, // possibly unused
    _unk_B0: u32, // possibly unused
    pSpriteTrackPlace1st: *anyopaque, // FIXME: swrSprite typedef
    pSpriteTrackPlace2nd: *anyopaque, // FIXME: swrSprite typedef
    pSpriteTrackPlace3rd: *anyopaque, // FIXME: swrSprite typedef
    pSpriteTrackPlaceNone: *anyopaque, // FIXME: swrSprite typedef
    pSpriteTrackBorder: *anyopaque, // FIXME: swrSprite typedef
    pSpriteStatBar: *anyopaque, // FIXME: swrSprite typedef
    PodiumCharacters: [3]u8, // TODO: character typedef
    _unk_CF: u8, // possibly unused
};

const HangMenuScreen = enum(i32) {
    None = -1,
    // TODO
};

const HangRoom = enum(i32) {
    Shop = 0,
    Junkyard = 1,
    Hangar = 2,
    Cantina = 3,
};

const HangCameraState = enum(i32) {
    None = -1,
    _unk_0 = 0,
    CounterBuyParts = 1,
    _unk_2 = 2,
    _unk_3 = 3,
    JunkyardPart01 = 4,
    JunkyardPart02 = 5,
    JunkyardPart03 = 6,
    JunkyardPart04 = 7,
    JunkyardPart05 = 8,
    JunkyardPart06 = 9,
    JunkyardPart07 = 10,
    JunkyardPart08 = 11,
    JunkyardPart09 = 12,
    JunkyardPart10 = 13,
    JunkyardPart11 = 14,
    JunkyardPart12 = 15,
    JunkyardPart13 = 16,
    JunkyardPart14 = 17,
    JunkyardPart15 = 18,
    JunkyardPart16 = 19,
    InspectDefault = 20,
    InspectCockpit = 21,
    InspectEngine1 = 22,
    InspectEngine2 = 23,
    InspectEngine3 = 24,
    InspectEngine4 = 25,
    InspectPT01 = 26,
    InspectPT02 = 27,
    InspectPT03 = 28,
    InspectPT04 = 29,
    InspectCharacter = 30,
    InspectUpgrades1 = 31, // traction, air brake
    InspectUpgrades2 = 32, // turning, cooling
    InspectUpgrades3 = 33, // accel, repair
    InspectUpgrades4 = 34, // top speed
    _unk_35 = 35,
    CantinaHolotableFar = 36, // (vehicle, etc.)
    CantinaHolotableNear = 37, // (track, circuit, etc.)
    CantinaEntryCutscene = 39,
};

//const Payout = extern struct {
//    Pos1: i16,
//    Pos2: i16,
//    Pos3: i16,
//    Pos4: i16,
//};

//const HangFlags = enum(u32) {
//    HangActive,
//    _unk_01,
//    _unk_02,
//    _unk_03,
//};

const JunkyardPart = extern struct {
    Category: i8,
    Level: u8,
    Health: u8,
};

// HELPERS

// ...
