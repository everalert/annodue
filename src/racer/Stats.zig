const std = @import("std");

pub const Stats = extern struct {
    AntiSkid: f32,
    TurnResponse: f32,
    MaxTurnRate: f32,
    Acceleration: f32,
    MaxSpeed: f32,
    AirBrakeInv: f32,
    DecelInv: f32,
    BoostThrust: f32,
    HeatRate: f32,
    CoolRate: f32,
    HoverHeight: f32,
    RepairRate: f32,
    BumpMass: f32,
    DamageImmunity: f32,
    ISectRadius: f32,
};

pub const TestStats = extern struct {
    AntiSkid: f32,
    TurnResponse: f32,
    MaxTurnRate: f32,
    Acceleration: f32,
    MaxSpeed: f32,
    AirBrakeInv: f32,
    DecelInv: f32,
    BoostThrust: f32,
    HeatRate: f32,
    CoolRate: f32,
    HoverHeight: f32,
    RepairRate: f32,
    BumpMass: f32,
    DamageImmunity: f32,
    BaseHoverHeight: f32,
    ISectRadius: f32,
};
