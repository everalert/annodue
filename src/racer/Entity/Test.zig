const std = @import("std");

const e = @import("entity.zig");
const mat = @import("../Matrix.zig");
const Mat4x4 = mat.Mat4x4;
const vec = @import("../Vector.zig");
const Vec3 = vec.Vec3;
const model = @import("../Model.zig");
const ModelMesh = model.ModelMesh;

const TestStats = @import("../Stats.zig").TestStats;

// GAME FUNCTIONS

pub const HandleTerrain: *fn (*Test) callconv(.C) void = @ptrFromInt(0x476EA0);

pub const fnStage14: *fn (*Test) callconv(.C) void = @ptrFromInt(0x46D170);
pub const fnStage18: *fn (*Test) callconv(.C) void = @ptrFromInt(0x47AB40);
pub const fnStage1C: *fn (*Test) callconv(.C) void = @ptrFromInt(0x47B520);
pub const fnStage20: *fn (*Test) callconv(.C) void = @ptrFromInt(0x470610);
pub const fnEvent: *fn (*Test, magic: *e.MAGIC_EVENT, payload: u32) callconv(.C) void = @ptrFromInt(0x474D80);

// GAME CONSTANTS

pub const DoRespawn: *fn (*Test, spline_offset: f32) callconv(.C) void = @ptrFromInt(0x473F40);

// GAME TYPEDEFS

pub const SIZE: usize = e.EntitySize(.Test);

pub const PLAYER_PTR_ADDR: usize = 0x4D78A8;
pub const PLAYER_PTR: *usize = @ptrFromInt(PLAYER_PTR_ADDR);
// TODO: double pointer; original data probably game state struct holding the ptr
pub const PLAYER: **Test = @ptrFromInt(PLAYER_PTR_ADDR);
pub const PLAYER_SLICE: **[SIZE]u8 = @ptrFromInt(PLAYER_PTR_ADDR); // TODO: convert to many-item pointer

// GAME TYPEDEFS

// TODO: testing to assert entity size
// TODO: finish filling in this
// TODO: renaming to proper style
pub const Test = extern struct {
    entity_magic: u32,
    entity_flags: u32,
    spawn: extern struct { position: [3]f32, orientation: [3]f32 }, // TODO: typedef, Location
    transform: Mat4x4,
    flags1: TEST_FLAGS1,
    flags2: TEST_FLAGS2,
    _unk_0068_006B: [4]u8,
    stats: TestStats,
    _unk_00AC_00DB: [0x30]u8, // TODO: typedef, LapCompStruct
    _unk_00DC_00DF: [4]u8, // lap timing/completion related
    lapComp: f32,
    lapCompPrev: f32,
    lapCompMax: f32,
    _unk_00EC_010F: [0x110 - 0xEC]u8, // all lap timing/completion related
    idleTick: f32, // ticks up when following addr <= 8; see fn_47FDD0
    moveTick: i32, // resets to 0 when going backward on track, and tick up to max 200 when moving fwd
    _unk_0118_013B: [0x13C - 0x118]u8,
    _unkptr_013C: *anyopaque, // collision-related?
    _unk_0140_terrainModel: *ModelMesh, // terrain-related struct
    _unkvec3_0144: Vec3,
    speedLoss: f32,
    _unkvec3_0154: Vec3,
    _unkvec3_0160: Vec3, // down direction vector?
    positionPrev: Vec3,
    positionDeath: Vec3,
    _vert_motion: f32,
    _ground_z: f32,
    _thrust: f32,
    _grav_mult: f32,
    _unkvec3_0194: Vec3, // up or down direction vector?
    speed: f32,
    accelThrust: f32,
    accelBoost: f32,
    _speed_mult: f32,
    _fall_float_rate: f32,
    _fall_float_value: f32,
    velocity: Vec3,
    velocitySlope: Vec3,
    velocityCollision: Vec3,
    velocityCollisionOpponent: Vec3,
    slide: f32,
    turnRate: f32,
    turnRateTarget: f32,
    _turn_modifier: f32,
    _unk_01F8_01FF: [8]u8,
    tiltAngleTarget: f32,
    tiltAngle: f32,
    tiltManualMult: f32,
    _unk_020C_020F: [4]u8,
    boostChargeStatus: u32, // 0=idle, 1=charging, 2=ready
    boostChargeTimer: f32,
    temperature: f32, // 'heat'
    gravityTubeAngle: f32,
    _unk_0220_022B: [12]u8,
    _stat_mult: f32,
    _unk_0230_023F: [16]u8,
    speedOffset: f32, // fast terrain
    speedMult: f32, // slow terrain
    tractionMultIce: f32,
    tractionMultGeneral: f32, // 0.80 off throttle, 0.45 slide
    _unk_0250_0253: [4]u8,
    _unkptr_0254: *anyopaque,
    _unk_0258_026B: [20]u8,
    _collision_toggles: u32,
    engineHealthMin: [6]f32, // TODO: typedef
    engineHealth: [6]f32, // TODO: typedef
    engineStatus: [6]u32, // TODO: typedef
    _unk_02B8_02BB: [4]u8,
    repairTimer: f32,
    damageWarningTimer: f32,
    damageTotal: f32,
    fallTimer: f32,
    nextPosition: Vec3, // TODO: typedef, Location
    nextRotation: Vec3, // TODO: typedef, Location
    nextRotationDelta: Vec3,
    _unk_02F0_02FB: [12]u8, // correct
    pitch: f32, // -0.8..0.8
    _unk_0300_030B: [12]u8,
    respawnInvincibilityTimer: f32,
    _unk_0310_032F: [32]u8, // correct
    engineExhaustSizeL: f32,
    engineExhaustSizeR: f32,
    _unk_0338_0343: [12]u8, // wrong
    _unkptr_0344: *anyopaque,
    _unkptr_0348: *anyopaque,
    _unkptr_034C: *anyopaque,
    _unk_0350: Mat4x4,
    EngineXfR: Mat4x4,
    EngineXfL: Mat4x4,
    EngineXfR2: Mat4x4,
    EngineXfL2: Mat4x4,
    CockpitXf: Mat4x4,
    EnergyBinderXf: Mat4x4,
    _unk_0510: Mat4x4,
    _unk_0550: Mat4x4,
    _unk_0590: Mat4x4,
    _unk_05D0: Mat4x4,
    _unk_0610: Mat4x4,
    _unk_0650: Mat4x4,
    _unk_0690: Mat4x4,
    _unk_06D0_0A4F: [0x0A50 - 0x6D0]u8,
    _unk_0A50: Mat4x4,
    _unk_0A90: Mat4x4,
    _unk_0AD0_12CF: [0x12D0 - 0xAD0]u8,
    _unk_12D0: Mat4x4,
    _unk_1310: Mat4x4,
    _unk_1350: Mat4x4,
    ScrapeSparkXf: Mat4x4,
    _unk_13D0: Mat4x4,
    EngineExhaustXfR: Mat4x4,
    EngineExhaustXfL: Mat4x4,
    _unk_1490: Mat4x4,
    _unk_14D0: Mat4x4,
    _unk_1510_1F27: [SIZE - 0x1510]u8,
};

// TODO: testing assert size 32 bits
pub const TEST_FLAGS1 = packed struct {
    IN_COUNTDOWN: bool, // 0..3 may be 4-bit int for race state
    IN_RACE: bool,
    _02: bool,
    _03: bool,
    IS_MOVING: bool,
    RACE_NOT_ENDED: bool,
    _06: bool,
    IN_AUTOPILOT: bool,
    _08: bool,
    IS_BRAKING: bool,
    IS_REPAIRING: bool,
    QUEUE_RESET: bool,
    QUEUE_RESPAWN: bool,
    IS_RESPAWN_INVINCIBLE: bool,
    IS_DEAD: bool,
    _15: bool,
    _16: bool,
    _17: bool,
    _18: bool,
    CAMERA_ENGINE: bool,
    CAMERA_LOOKBACK: bool,
    BOOST_CAN_CHARGE: bool,
    _22: bool,
    IS_BOOSTING: bool,
    _24: bool,
    IN_ZON: bool,
    IN_ZOFF: bool,
    CAN_STOP: bool,
    _28: bool,
    _29: bool,
    WAS_BOOSTING: bool, // on prev frame
    _31: bool,
};

// TODO: testing assert size 32 bits
pub const TEST_FLAGS2 = packed struct {
    ON_SWMP_TERRAIN: bool,
    _01: bool,
    IS_NOT_ACCELERATING: bool,
    IS_SLIDING: bool,
    _04: bool,
    ON_SIDE_TERRAIN: bool,
    ON_MIRR_TERRAIN: bool,
    _07: bool,
    _08: bool,
    IS_AIRBORNE: bool,
    TILT_DISABLED: bool, // 'magnet mode'; TODO: confirm if terrain related and rename accordingly
    CAN_BOOST_START: bool,
    BOOST_START_CANCELLED: bool,
    BOOST_START_ACTIVATED: bool,
    IS_EXPLODING: bool,
    IS_EXPLODING_RIGHT_SPIN: bool, // TODO: confirm if @14 is always on when @15 or @16 are
    IS_EXPLODING_LEFT_SPIN: bool,
    _17: bool,
    ON_LAVA_TERRAIN: bool,
    ON_FALL_TERRAIN: bool,
    ON_SOFT_TERRAIN: bool,
    _21: bool,
    _22: bool,
    ON_FLAT_TERRAIN: bool,
    _24: bool,
    RACE_COMPLETE: bool,
    _26: bool,
    _27: bool,
    _28: bool,
    _29: bool,
    _30: bool,
    _31: bool,
};

// HELPERS

// ...
