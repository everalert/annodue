const std = @import("std");
const e = @import("entity.zig");
const TestStats = @import("../Stats.zig").TestStats;

pub const SIZE: usize = e.EntitySize(.Test);

pub const PLAYER_PTR_ADDR: usize = 0x4D78A8;
pub const PLAYER_PTR: *usize = @ptrFromInt(PLAYER_PTR_ADDR);
// TODO: double pointer; original data probably game state struct holding the ptr
pub const PLAYER: **Test = @ptrFromInt(PLAYER_PTR_ADDR);
pub const PLAYER_SLICE: **[SIZE]u8 = @ptrFromInt(PLAYER_PTR_ADDR); // TODO: convert to many-item pointer

// TODO: testing to assert entity size
// TODO: finish filling in this
pub const Test = extern struct {
    entity_magic: u32,
    entity_flags: u32,
    spawn: extern struct { position: [3]f32, orientation: [3]f32 }, // TODO: typedef
    transform: [16]f32, // TODO: typedef
    flags1: u32, // TODO: enum
    flags2: u32, // TODO: enum
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
    _unkptr_0140: *anyopaque, // terrain-related struct
    _unkvec3_0144: [3]f32, // TODO: typedef
    speedLoss: f32,
    _unkvec3_0154: [3]f32, // TODO: typedef
    _unkvec3_0160: [3]f32, // TODO: typedef, down direction vector?
    positionPrev: [3]f32, // TODO: typedef
    positionDeath: [3]f32, // TODO: typedef
    _vert_motion: f32,
    _ground_z: f32,
    _thrust: f32,
    _grav_mult: f32,
    _unkvec3_0194: [3]f32, // TODO: typedef, up or down direction vector?
    speed: f32,
    accelThrust: f32,
    accelBoost: f32,
    _speed_mult: f32,
    _fall_float_rate: f32,
    _fall_float_value: f32,
    velocity: [3]f32, // TODO: typedef
    velocitySlope: [3]f32, // TODO: typedef
    velocityCollision: [3]f32, // TODO: typedef
    velocityCollisionOpponent: [3]f32, // TODO: typedef
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
    nextPosition: [3]f32, // TODO: typedef
    nextRotation: [3]f32, // TODO: typedef
    nextRotationDelta: [3]f32, // TODO: typedef
    _unk_02F0_02FB: [12]u8,
    pitch: f32, // -0.8..0.8
    _unk_0300_030B: [12]u8,
    respawnInvincibilityTimer: f32,
    _unk_0310_032F: [28]u8,
    engineExhaustSizeL: f32,
    engineExhaustSizeR: f32,
    _unk_0338_0343: [12]u8,
    _unkptr_0344: *anyopaque,
    _unkptr_0348: *anyopaque,
    _unkptr_034C: *anyopaque,
    _unk_0350_1F27: [SIZE - 0x350]u8,
};

// TODO: enum
//0x0060 (u32)  Flags
//	@0..3	'racing status'? all cleared when countdown ends, except @01 (see fn_474D80 "Go!!")
//	1<<00  in countdown?
//	1<<01	in race (racing), stays on while driving;  turned on when countdown ends (see fn_474D80 "Go!!")
//			ref in 46CF00, checked to see if on while 00,02,03 are all off
//	1<<02  probably completion status related
//	1<<03  probably completion status related
//	1<<04  ??? ref in 470610; braking related
//			set to 1 when accelerating
//			will only go back to 0 when pressing brake at very low speed
//			will not go to 0 even at a standstill until you press brake
//			nor if you press brake before going slow enough (doesn't buffer)
//			only other time observed is when you die until you start accelerating again
//	1<<05  race not ended?
//			set to 1 in prerace media cutscene, stays on throughout race until crossing line
//			referenced in 46CE30, 46CF00, 47B520, 479E10
//	1<<06  ??? referenced in 47FDD0_LapCompletion, 46CF00_CalcTargetTurnRate, 470610
//	1<<07  in autopilot
//	1<<08  ??? referenced in 46B670, 46D170; related to going backward timer 0x110
//	1<<09  is braking
//	1<<10  is repairing;  set on during postrace
//	1<<11  'reset pod' from LP;  ref in 46BEC0, Jdge_UiDrawRace_462B20; next to isdead
//	1<<12  'respawn pod' from LP
//			turns on when in autopilot, race not finished and deathspeed triggered (lmao)
//			refs in 46BEC0, 4611F0, 46D170, 40B150, 47B520, 47B000_DeathSpeedHandler
//			if you turn this on you die
//	1<<13  has respawn invincibility
//	1<<14  is dead
//	1<<15  ??? - referenced in 46B670, seems race completion-related
//	1<<16  ??? - referenced in 46B670, seems race completion-related
//	1<<17  'TP pod to next spline point?' from LP;  ref in 46D170
//	1<<18  ??? ref in 47B520
//	1<<19  camera engine view
//	1<<20  camera looking back
//	1<<21  is able to charge boost
//	1<<22  ???  called from 4783E0_ApplyAcceleration(), 470610
//			locks thrust to 1.2 (from LP)
//	1<<23  is boosting
//	1<<24  ???  is going uphill? sudden pitch change flag? ??? ref in 4774F0; gravity related
//	1<<25  in zon state;  not just on zon terrain, but presumably triggered by hitting zon terrain
//	1<<26  in 'zoff' state;  not just on zoff terrain
//			causes a hover state that automatically returns to 0 rotation with no input
//			stays on for the duration of the extended hover you sometimes get leaving tubes
//			presumably set by touching zoff terrain, but conditions not confirmed
//	1<<27  is stopped or stopping?
//			set on when at low but not necessarily 0 speed
//			similar to 1<<04 but the speed threshold seems a little higher
//	1<<28  ??? tested in speed function (from LP)
//	1<<29
//	1<<30  ??? was boosting last frame
//	1<<31  ??? ref in 46BEC0, 41D930, 46D170, 477AD0; related to tilting, flags2 1<<27
//0x0064 (u32)  Flags
//	1<<00  on swamp terrain
//	1<<01  ??? ref in 46D170
//	1<<02  is not accelerating
//	1<<03  is sliding? - confirmed directly switched on when airborne; also turns on with button?
//	1<<04  ???  related to sliding as a check unsure what difference is
//	1<<05  on side terrain;  seems to make AI manual tilt, also ref in 4783E0_ApplyAcceleration()
//	1<<06  on mirr terrain
//	1<<07  ??? elevation flag
//			BWR tunnel/ice field/under some arches
//			seems to activate when entering the loading area, not specific spots
//			AMR pre-canyon area
//			BEC 1st shortcut
//			SR/ABY start and end bridges
//			apparently tested in deathspeed function (from LP)
//	1<<08
//	1<<09  is airborne
//	1<<10  tilt disabled, aka "magnet mode"
//	1<<11  Boost Start Window;  ref in 45E200
//	1<<12  boost start cancel (from LP)
//	1<<13  boost start (from LP);  ref in 40B5E0
//	1<<14  is exploding
//	1<<15  is exploding;  left spinout (from LP),  ref in 46E150
//			rel to flags1 1<<05 (race not ended) and flags2 1<<26 ('zoff state')
//	1<<16  is exploding;  right spinout (from LP),  ref in 46E150
//			rel to flags1 1<<05 (race not ended) and flags2 1<<26 ('zoff state')
//	1<<17
//	1<<18  on lava terrain
//	1<<19  on fall terrain
//	1<<20  on soft terrain;  e.g. BC beach
//	1<<21  ??? written during track subsection load (see EXE+51B17)
//	1<<22  ??? ref in 479E10; set or unset based on 1<<23, 'condition for flat' from LP
//	1<<23  on flat terrain (from LP);  ref in 470610, 479E10
//	1<<24  ??? set on at start of race BTC
//	1<<25  race complete;  used for UI (from LP)
//	1<<26  ??? called from 46CF00, 470610, 47B520; related to turn rate and autopilot
//	1<<27  grounded? (from LP)
//			called from 4783E0_ApplyAccel, 41D930, 470610
//	1<<28  immunity? (from LP)
//			called from 4783E0_ApplyAccel, 46D170, 470610, 47B520, 47B000_DeathSpeed
//	1<<29  ??? ref in 47AB40, 47B520, 479E10, 47B000_DeathSpeedHandler
//	1<<30
//	1<<31  ??? called from 4783E0_ApplyAcceleration()
