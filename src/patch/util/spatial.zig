const std = @import("std");

const m = std.math;
const deg2rad = m.degreesToRadians;
const rad2deg = m.radiansToDegrees;

const rm = @import("racer").Matrix;
const rv = @import("racer").Vector;
const Vec2 = rv.Vec2;
const Vec3 = rv.Vec3;
const Vec4 = rv.Vec4;
const Mat4x4 = rm.Mat4x4;

const Quat = Vec4;
const AxisAngle = Vec4;

// TODO: move stuff from cam7 here

// FIXME: replace uses of this with in-game functions
pub const Pos3D = extern struct {
    const Self = @This();
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn dif(self: *Self, other: *Self) Self {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn distance(self: *Self, other: *Self) f32 {
        const step = self.dif(other);
        return std.math.sqrt(step.x * step.x + step.y * step.y + step.z * step.z);
    }

    pub fn distanceXY(self: *Self, other: *Self) f32 {
        const step = self.dif(other);
        return std.math.sqrt(step.x * step.x + step.y * step.y);
    }
};

pub fn quat_mul(out: *Quat, in1: *const Quat, in2: *const Quat) void {
    out.* = .{
        .x = in1.w * in2.x + in1.x * in2.w + in1.y * in2.z - in1.z * in2.y,
        .y = in1.w * in2.y + in1.y * in2.w + in1.z * in2.x - in1.x * in2.z,
        .z = in1.w * in2.z + in1.z * in2.w + in1.x * in2.y - in1.y * in2.x,
        .w = in1.w * in2.w - in1.x * in2.x - in1.y * in2.y - in1.z * in2.z,
    };
}

// axis-angle
pub fn quat_setAA(out: *Quat, in: *const AxisAngle) void {
    std.debug.assert(1 == rv.Vec3_Magnitude(@ptrCast(in)));

    out.x = in.x * @sin(in.w);
    out.y = in.y * @sin(in.w);
    out.z = in.z * @sin(in.w);
    out.w = @cos(in.w);
}

// axis-angle
pub fn quat_getAA(in: *const Quat, out: *AxisAngle) void {
    std.debug.assert(1 >= in.w);

    out.w = m.acos(in.w) * 2;
    const s: f32 = @sqrt(1 - in.w * in.w);
    if (s < 0.001) {
        out.x = in.x;
        out.y = in.y;
        out.z = in.z;
    } else {
        out.x = in.x / s;
        out.y = in.y / s;
        out.z = in.z / s;
    }
}

pub fn mat4x4_getQuaternion(in: *const Mat4x4, out: *Quat) void {
    out.w = m.sqrt(1.0 + in.X.x + in.Y.y + in.Z.z) / 2;
    const w4: f32 = 4 * out.w;
    out.x = (in.Z.y - in.Y.z) / w4;
    out.y = (in.X.z - in.Z.x) / w4;
    out.z = (in.Y.x - in.X.y) / w4;
}

// adapted from Mat4x4_InitQuat
pub fn mat4x4_setQuaternion(out: *Mat4x4, in: *const Quat) void {
    const w_sin: f32 = @sin(in.w);
    const w_cos: f32 = @cos(in.w);

    if (in.z > 0.999) { // 0x3F7FBE77
        out.X = .{ .x = w_cos, .y = w_sin, .z = 0.0, .w = 0.0 };
        out.Y = .{ .x = -w_sin, .y = w_cos, .z = 0.0, .w = 0.0 };
        out.Z = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 };
        return;
    }

    if (in.z < -0.999) { // 0xBF7FBE77
        out.X = .{ .x = w_cos, .y = -w_sin, .z = 0.0, .w = 0.0 };
        out.Y = .{ .x = w_sin, .y = w_cos, .z = 0.0, .w = 0.0 };
        out.Z = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 };
        return;
    }

    const sqx = in.x * in.x;
    const sqy = in.y * in.y;
    const sqy_cos = sqy * w_cos;
    const sqx_cos = sqx * w_cos;
    const sqxy_inv = 1.0 - sqx - sqy;
    const sqxy = 1.0 - sqxy_inv;
    const w_cos_inv = 1.0 - w_cos;

    out.X.x = (sqx_cos * sqxy_inv + sqy_cos) / sqxy + sqx;
    out.Y.y = (sqy_cos * sqxy_inv + sqx_cos) / sqxy + sqy;
    out.Z.z = sqx_cos + sqy_cos + sqxy_inv;
    out.X.y = in.y * in.x * w_cos_inv + w_sin * in.z;
    out.Y.x = in.y * in.x * w_cos_inv - w_sin * in.z;
    out.X.z = in.z * in.x * w_cos_inv - w_sin * in.y;
    out.Z.x = in.z * in.x * w_cos_inv + w_sin * in.y;
    out.Y.z = in.z * in.y * w_cos_inv + w_sin * in.x;
    out.Z.y = in.z * in.y * w_cos_inv - w_sin * in.x;

    out.X.w = 0.0;
    out.Y.w = 0.0;
    out.Z.w = 0.0;
}

pub fn mat4x4_getEuler(mat: *const Mat4x4, euler: *Vec3) void {
    const t1: f32 = m.atan2(f32, mat.Y.z, mat.Z.z); // Z
    const c2: f32 = m.sqrt(mat.X.x * mat.X.x + mat.X.y * mat.X.y);
    const t2: f32 = m.atan2(f32, -mat.X.z, c2); // Y
    const c1: f32 = m.cos(t1);
    const s1: f32 = m.sin(t1);
    const t3: f32 = m.atan2(f32, s1 * mat.Z.x - c1 * mat.Y.x, c1 * mat.Y.y - s1 * mat.Z.y); // X
    euler.x = t3;
    euler.y = t2;
    euler.z = t1;
}

pub fn mat4x4_getRow(in: *const Mat4x4, out: *Vec3, row: usize) void {
    const _in: *const [4][4]f32 = @ptrCast(in);
    out.x = _in[0][row];
    out.y = _in[1][row];
    out.z = _in[2][row];
}

pub fn mat4x4_setRotation(out: *Mat4x4, in: *const Vec3) void {
    rm.Mat4x4_SetRotation(out, rad2deg(f32, in.x), rad2deg(f32, in.y), rad2deg(f32, in.z));
}

// TODO: fix assertion
const UP: Vec3 = .{ .x = 0, .y = 0, .z = -1 };
pub fn vec3_dirToEuler(out: *Vec3, in: *const Vec3) void {
    //std.debug.assert(m.fabs(1.0 - rv.Vec3_Mag(in)) < m.floatEps(f32));
    const H: f32 = m.atan2(f32, -in.x, in.y); // heading; X
    const P: f32 = m.asin(in.z); // pitch; Y
    const W0 = Vec3{ .x = -in.y, .y = in.x }; // wings; 'right'?
    var U0: Vec3 = undefined;
    rv.Vec3_Cross(&U0, &W0, in);
    const B: f32 = m.atan2(f32, rv.Vec3_Dot(&W0, &UP), rv.Vec3_Dot(&U0, &UP)); // banking; Z
    out.* = .{ .x = H, .y = P, .z = B };
}

// TODO: fix assertion
pub fn vec3_dirToEulerXY(out: *Vec3, in: *const Vec3) void {
    //std.debug.assert(m.fabs(1.0 - rv.Vec3_Mag(in)) < m.floatEps(f32));
    const H: f32 = m.atan2(f32, -in.x, in.y); // heading; X
    const P: f32 = m.asin(in.z); // pitch; Y
    out.* = .{ .x = H, .y = P };
}

// NOTE: reimpl because in-game function causes side effects somehow
/// @return true if normalization possible
pub inline fn vec3_norm(out: *Vec3) bool {
    const mag: f32 = rv.Vec3_Mag(out);
    if (m.fabs(mag) >= m.floatEps(f32)) {
        const scale = 1 / mag;
        rv.Vec3_Scale(out, scale, out);
        return true;
    }
    return false;
}

pub inline fn vec3_mul3(out: *Vec3, x: f32, y: f32, z: f32) void {
    out.x *= x;
    out.y *= y;
    out.z *= z;
}

pub fn mmul(comptime n: u32, in1: *[n][n]f32, in2: *[n][n]f32, out: *[n][n]f32) void {
    inline for (0..n) |i| {
        inline for (0..n) |j| {
            var v: f32 = 0;
            inline for (0..n) |k| v += in1[i][k] * in2[k][j];
            out[i][j] = v;
        }
    }
}

// TODO: move damping functions elsewhere?

pub inline fn vec3_damp(out: *Vec3, in: *const Vec3, t: f32, dt: f32) void {
    out.x = f32_damp(out.x, in.x, t, dt);
    out.y = f32_damp(out.y, in.y, t, dt);
    out.z = f32_damp(out.z, in.z, t, dt);
}

pub inline fn f32_damp(from: f32, to: f32, t: f32, dt: f32) f32 {
    if (m.fabs(to - from) < m.floatEps(f32)) return to;
    return std.math.lerp(from, to, 1 - std.math.exp(-t * dt));
}
