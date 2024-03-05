const Self = @This();

const std = @import("std");

const m = std.math;
const deg2rad = m.degreesToRadians;

const w32 = @import("zigwin32");
const w32wm = w32.ui.windows_and_messaging;
const POINT = w32.foundation.POINT;
const RECT = w32.foundation.RECT;

const GlobalState = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFn;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");
const rc = @import("util/racer_const.zig");

const mem = @import("util/memory.zig");

const PLUGIN_NAME: [*:0]const u8 = "Cam7";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// FIXME: find a good hook spot where the game is naturally updating the camera
// so that the pause stuff is handled for us
// FIXME: figure out how to load all map chunks at once instead of piecemeal
// TODO: controls = ???
//   - drone-style controls as an option for sure tho

// TODO: move to lib, or replace with real lib
const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    inline fn magnitude(self: *const Vec3) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    inline fn cross(self: *const Vec3, other: *const Vec3) Vec3 {
        return .{
            .x = self.y * other.z - self.z - other.y,
            .y = self.z * other.x - self.x - other.z,
            .z = self.x * other.y - self.y - other.x,
        };
    }

    inline fn normalize(self: *const Vec3) Vec3 {
        const mul: f32 = 1 / self.magnitude();
        return .{
            .x = self.x * mul,
            .y = self.y * mul,
            .z = self.z * mul,
        };
    }

    inline fn apply_deadzone(self: *Vec3, dz: f32) void {
        if (self.magnitude() < dz) {
            self.x = 0;
            self.y = 0;
            self.z = 0;
        }
    }

    inline fn damp(self: *Vec3, target: *const Vec3, t: f32, dt: f32) void {
        self.x = std.math.lerp(self.x, target.x, 1 - std.math.exp(-t * dt));
        self.y = std.math.lerp(self.y, target.y, 1 - std.math.exp(-t * dt));
        self.z = std.math.lerp(self.z, target.z, 1 - std.math.exp(-t * dt));
    }
};

const Cam7 = extern struct {
    const rotation_damp: f32 = 48;
    const rotation_speed: f32 = 180;
    const motion_damp: f32 = 8;
    const motion_speed: f32 = 450;
    var saved_camstate_index: ?u32 = null;
    var cam_mat4x4: [4][4]f32 = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
    var xcam_rot: Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    var xcam_rot_target: Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    var xcam_rotation: Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    var xcam_rotation_target: Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    var xcam_motion: Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    var xcam_motion_target: Vec3 = .{ .x = 0, .y = 0, .z = 0 };

    fn update_cam_from_rot(euler: *const Vec3) void {
        // TODO: probably can do better than this, at least more efficient
        // if not switching to quaternions or smth
        var x: [3][3]f32 = .{
            .{ m.cos(euler.x), -m.sin(euler.x), 0 },
            .{ m.sin(euler.x), m.cos(euler.x), 0 },
            .{ 0, 0, 1 },
        };
        var y: [3][3]f32 = .{
            .{ m.cos(euler.y), 0, m.sin(euler.y) },
            .{ 0, 1, 0 },
            .{ -m.sin(euler.y), 0, m.cos(euler.y) },
        };
        var z: [3][3]f32 = .{
            .{ 1, 0, 0 },
            .{ 0, m.cos(euler.z), -m.sin(euler.z) },
            .{ 0, m.sin(euler.z), m.cos(euler.z) },
        };
        var out: [3][3]f32 = undefined;
        mmul(3, &z, &x, &out);
        mmul(3, &y, &out, &out);
        @memcpy(@as(*[3]f32, @ptrCast(&Cam7.cam_mat4x4[0])), &out[0]);
        @memcpy(@as(*[3]f32, @ptrCast(&Cam7.cam_mat4x4[1])), &out[1]);
        @memcpy(@as(*[3]f32, @ptrCast(&Cam7.cam_mat4x4[2])), &out[2]);
    }

    fn update_rot_from_cam(euler: *Vec3) void {
        const mat = &Cam7.cam_mat4x4;
        const t1: f32 = m.atan2(f32, mat[1][2], mat[2][2]); // Z
        const c2: f32 = m.sqrt(mat[0][0] * mat[0][0] + mat[0][1] * mat[0][1]);
        const t2: f32 = m.atan2(f32, -mat[0][2], c2); // Y
        const c1: f32 = m.cos(t1);
        const s1: f32 = m.sin(t1);
        const t3: f32 = m.atan2(f32, s1 * mat[2][0] - c1 * mat[1][0], c1 * mat[1][1] - s1 * mat[2][1]); // X
        euler.x = -t3;
        euler.y = t2;
        euler.z = t1;
    }
};

// TODO: move to vec lib, or find glm equivalent
fn mmul(comptime n: u32, in1: *[n][n]f32, in2: *[n][n]f32, out: *[n][n]f32) void {
    inline for (0..n) |i| {
        inline for (0..n) |j| {
            var v: f32 = 0;
            inline for (0..n) |k| v += in1[i][k] * in2[k][j];
            out[i][j] = v;
        }
    }
}

const camstate_ref_addr: u32 = rc.CAM_METACAM_ARRAY_ADDR + 0x170; // = metacam index 1 0x04

fn RestoreSavedCam() void {
    if (Cam7.saved_camstate_index) |i| {
        _ = mem.write(camstate_ref_addr, u32, i);
        Cam7.saved_camstate_index = null;
    }
}
fn SaveSavedCam() void {
    Cam7.saved_camstate_index = mem.read(camstate_ref_addr, u32);
    const camstate_mat4_addr: u32 = rc.CAM_CAMSTATE_ARRAY_ADDR + Cam7.saved_camstate_index.? * rc.CAM_CAMSTATE_ITEM_SIZE + 0x14;
    @memcpy(
        @as(*[16]f32, @ptrCast(&Cam7.cam_mat4x4[0])),
        @as([*]f32, @ptrFromInt(camstate_mat4_addr)),
    );
    Cam7.update_rot_from_cam(&Cam7.xcam_rot);
    @memcpy(@as(*[3]f32, @ptrCast(&Cam7.xcam_rot_target)), @as(*[3]f32, @ptrCast(&Cam7.xcam_rot)));
    _ = mem.write(camstate_ref_addr, u32, 31);
}

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return PLUGIN_NAME;
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return PLUGIN_VERSION;
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    // FIXME: this shouldn't be here normally, because game init overrides it
    // but for now we need it because hot-reload only calls here to re-init
    rf.swrCam_CamState_InitMainMat4(31, 1, @intFromPtr(&Cam7.cam_mat4x4), 0);
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    // FIXME: rework after OnLateInit added to hot reloading
    OnInit(gs, gv, initialized);
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    RestoreSavedCam();
    rf.swrCam_CamState_InitMainMat4(31, 0, 0, 0);
}

// HOOKS

export fn EarlyEngineUpdateA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    var buf: [127:0]u8 = undefined;
    _ = buf;

    _ = initialized;
    if (Cam7.saved_camstate_index) |_| {
        const a_lx: f32 = gv.InputGetXInputAxis(.StickLX);
        const a_ly: f32 = gv.InputGetXInputAxis(.StickLY);
        const a_rx: f32 = gv.InputGetXInputAxis(.StickRX);
        const a_ry: f32 = gv.InputGetXInputAxis(.StickRY);
        const a_t: f32 = (gv.InputGetXInputAxis(.TriggerL) - gv.InputGetXInputAxis(.TriggerR));

        Cam7.xcam_rotation.x = a_rx;
        Cam7.xcam_rotation.z = -a_ry;
        Cam7.xcam_rotation.apply_deadzone(0.05);
        if (Cam7.xcam_rotation.magnitude() > 1)
            Cam7.xcam_rotation = Cam7.xcam_rotation.normalize();
        //Cam7.xcam_rotation.damp(&Cam7.xcam_rotation_target, Cam7.rotation_damp, gs.dt_f);

        Cam7.xcam_rot_target.x = m.rem(f32, Cam7.xcam_rot_target.x + gs.dt_f * Cam7.rotation_speed / 360 * m.pi * 2 * Cam7.xcam_rotation.x, m.pi * 2) catch unreachable;
        Cam7.xcam_rot_target.y = 0;
        Cam7.xcam_rot_target.z = m.rem(f32, Cam7.xcam_rot_target.z + gs.dt_f * Cam7.rotation_speed / 360 * m.pi * 2 * Cam7.xcam_rotation.z, m.pi * 2) catch unreachable;

        Cam7.xcam_rot.damp(&Cam7.xcam_rot_target, Cam7.rotation_damp, gs.dt_f);
        Cam7.update_cam_from_rot(&Cam7.xcam_rot);

        const ang: f32 = m.atan2(f32, a_ly, a_lx);
        const mag: f32 = @min(m.sqrt(a_lx * a_lx + a_ly * a_ly), 1);
        Cam7.xcam_motion_target.x = mag * m.cos(ang - Cam7.xcam_rot.x);
        Cam7.xcam_motion_target.y = mag * m.sin(ang - Cam7.xcam_rot.x);
        Cam7.xcam_motion_target.z = a_t;
        Cam7.xcam_motion_target.apply_deadzone(0.05);
        if (Cam7.xcam_motion_target.magnitude() > 1)
            Cam7.xcam_motion_target = Cam7.xcam_motion_target.normalize();

        Cam7.xcam_motion.damp(&Cam7.xcam_motion_target, Cam7.motion_damp, gs.dt_f);

        Cam7.cam_mat4x4[3][0] += gs.dt_f * Cam7.motion_speed * Cam7.xcam_motion.x;
        Cam7.cam_mat4x4[3][1] += gs.dt_f * Cam7.motion_speed * Cam7.xcam_motion.y;
        Cam7.cam_mat4x4[3][2] += gs.dt_f * Cam7.motion_speed * Cam7.xcam_motion.z;

        if (gv.InputGetKbPressed(.@"0")) RestoreSavedCam();
    } else {
        if (gv.InputGetKbPressed(.@"0")) SaveSavedCam();
    }
}
