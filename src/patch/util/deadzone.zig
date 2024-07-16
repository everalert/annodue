const std = @import("std");

const m = std.math;

const rv = @import("racer").Vector;
const Vec2 = rv.Vec2;
const Vec3 = rv.Vec3;

// TODO: more sophisticated range limiting that allows for more freedom?

// TODO: testing, e.g. 0.05..0.95 (0.35) -> mag 0.333..
pub inline fn vec2_applyDeadzone(out: *Vec2, inner: f32, outer: f32, range: f32, fact: f32) void {
    const mag: f32 = rv.Vec2_Mag(out);

    if (mag <= inner) {
        out.* = .{ .x = 0, .y = 0 };
        return;
    }

    const scale: f32 = if (mag >= outer) (range / mag * fact) else ((mag - inner) / range / mag);
    rv.Vec2_Scale(out, scale, out);
}

// TODO: testing, e.g. 0.05..0.95 (0.35) -> mag 0.333..
// sm64-style deadzone
pub inline fn vec2_applyDeadzoneSq(out: *Vec2, inner: f32, range: f32, fact: f32) void {
    out.x = if (@fabs(out.x) < inner) 0 else out.x - -m.sign(out.x) * inner;
    out.y = if (@fabs(out.y) < inner) 0 else out.y - -m.sign(out.y) * inner;
    if (out.x == 0 and out.y == 0) return;

    const mag: f32 = rv.Vec2_Mag(out);
    const scale: f32 = if (mag > range) range / mag else fact;
    rv.Vec2_Scale(out, scale, out);
}

// TODO: testing, e.g. 0.05..0.95 (0.35) -> mag 0.333..
// sm64-style deadzone
pub inline fn vec3_applyDeadzoneSq(out: *Vec3, inner: f32, range: f32, fact: f32) void {
    out.x = if (@fabs(out.x) < inner) 0 else out.x - -m.sign(out.x) * inner;
    out.y = if (@fabs(out.y) < inner) 0 else out.y - -m.sign(out.y) * inner;
    out.z = if (@fabs(out.z) < inner) 0 else out.z - -m.sign(out.z) * inner;
    if (out.x == 0 and out.y == 0 and out.z == 0) return;

    const mag: f32 = rv.Vec3_Mag(out);
    const scale: f32 = if (mag > range) range / mag else fact;
    rv.Vec3_Scale(out, scale, out);
}

// TODO: testing, e.g. 0.05..0.95 (0.35) -> mag 0.333..
pub inline fn f32_applyDeadzone(out: *f32, inner: f32, outer: f32, range: f32, fact: f32) void {
    const mag: f32 = @fabs(out.*);

    if (mag <= inner) {
        out.* = 0;
        return;
    }

    const scale: f32 = if (mag >= outer) (range / mag * fact) else ((mag - inner) / range / mag);
    out.* *= scale;
}

// TODO: testing, e.g. 0.05..0.95 (0.35) -> mag 0.333..
// sm64-style deadzone
pub inline fn f32_applyDeadzoneSq(out: *f32, inner: f32, range: f32, fact: f32) void {
    out.* = if (@fabs(out.*) < inner) 0 else out.* - -m.sign(out.*) * inner;
    if (out.* == 0) return;

    const mag: f32 = @fabs(out.*);
    out.* *= if (mag > range) range / mag else fact;
}
