const Self = @This();

const std = @import("std");

const m = std.math;
const deg2rad = m.degreesToRadians;

const w32 = @import("zigwin32");
const w32wm = w32.ui.windows_and_messaging;
const POINT = w32.foundation.POINT;
const RECT = w32.foundation.RECT;
const VIRTUAL_KEY = w32.ui.input.keyboard_and_mouse.VIRTUAL_KEY;
const XINPUT_GAMEPAD_AXIS_INDEX = @import("util/input.zig").XINPUT_GAMEPAD_AXIS_INDEX;
const XINPUT_GAMEPAD_BUTTON_INDEX = @import("util/input.zig").XINPUT_GAMEPAD_BUTTON_INDEX;

const GlobalSt = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = r.functions;
const rc = r.constants;

const st = @import("util/active_state.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

const InputMap = @import("util/input.zig").InputMap;
const ButtonInputMap = @import("util/input.zig").ButtonInputMap;
const AxisInputMap = @import("util/input.zig").AxisInputMap;

const PLUGIN_NAME: [*:0]const u8 = "Cam7";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// FIXME: map visuals not updating when starting freecam while the game is pause-frozen
// FIXME: find a good hook spot where the game is naturally updating the camera
// so that the pause stuff is handled for us
// FIXME: cam seems to not always correct itself upright when switching?
// TODO: controls = ???
//   - drone-style controls as an option for sure tho
//   - mnk controls
// TODO: fog
// - option to disable fog entirely
// - user-selectable fog dist
// TODO: settings
// - control mapping
// - future fog stuff (see above)

const CamState = enum(u32) {
    None,
    FreeCam,
};

const Cam7 = extern struct {
    var enable: bool = false;
    var flip_look_x: bool = false;
    var flip_look_y: bool = false;

    const dz: f32 = 0.05;
    const rotation_damp: f32 = 48;
    const rotation_speed: f32 = 360;
    const motion_damp: f32 = 8;
    const motion_speed_xy: f32 = 650;
    const motion_speed_z: f32 = 350;
    const fog_dist: f32 = 7500;
    var cam_state: CamState = .None;
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

    var input_toggle_data = ButtonInputMap{ .kb = .@"0", .xi = .BACK };
    var input_look_x_data = AxisInputMap{ .kb_dec = .LEFT, .kb_inc = .RIGHT, .xi_inc = .StickRX, .kb_scale = 0.65 };
    var input_look_y_data = AxisInputMap{ .kb_dec = .DOWN, .kb_inc = .UP, .xi_inc = .StickRY, .kb_scale = 0.65 };
    var input_move_x_data = AxisInputMap{ .kb_dec = .A, .kb_inc = .D, .xi_inc = .StickLX };
    var input_move_y_data = AxisInputMap{ .kb_dec = .S, .kb_inc = .W, .xi_inc = .StickLY };
    var input_move_z_data = AxisInputMap{ .kb_dec = .SHIFT, .kb_inc = .SPACE, .xi_dec = .TriggerR, .xi_inc = .TriggerL };
    var input_toggle = input_toggle_data.inputMap();
    var input_look_x = input_look_x_data.inputMap();
    var input_look_y = input_look_y_data.inputMap();
    var input_move_x = input_move_x_data.inputMap();
    var input_move_y = input_move_y_data.inputMap();
    var input_move_z = input_move_z_data.inputMap();

    // TODO: mouse input
    // TODO: maybe normalizing XY stuff
    fn update_input(gf: *GlobalFn) void {
        input_toggle.update(gf);
        input_look_x.update(gf);
        input_look_y.update(gf);
        input_move_x.update(gf);
        input_move_y.update(gf);
        input_move_z.update(gf);
    }

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

const camstate_ref_addr: u32 = rc.CAM_METACAM_ARRAY_ADDR + 0x170; // = metacam index 1 0x04

fn CheckAndResetSavedCam() void {
    if (Cam7.saved_camstate_index == null) return;
    if (mem.read(camstate_ref_addr, u32) == 31) return;

    r.WriteEntityValue(.cMan, 0, 0x78, u32, 7);
    _ = x86.mov_eax_moffs32(0x453FA1, 0x50CA3C); // map visual flags-related check
    _ = x86.mov_ecx_u32(0x4539A0, 0x2D8); // fog dist, normal case
    _ = x86.mov_espoff_imm32(0x4539AC, 0x24, 0xBF800000); // fog dist, flags @0=1 case (-1.0)
    Cam7.saved_camstate_index = null;
    Cam7.cam_state = .None;
}

// FIXME: reset momentum to 0 when turning off cam, also probably apply same to CheckAndResetSavedCam
fn RestoreSavedCam() void {
    if (Cam7.saved_camstate_index) |i| {
        _ = mem.write(camstate_ref_addr, u32, i);
        r.WriteEntityValue(.cMan, 0, 0x78, u32, i);

        _ = x86.mov_eax_moffs32(0x453FA1, 0x50CA3C); // map visual flags-related check
        _ = x86.mov_ecx_u32(0x4539A0, 0x2D8); // fog dist, normal case
        _ = x86.mov_espoff_imm32(0x4539AC, 0x24, 0xBF800000); // fog dist, flags @0=1 case (-1.0)

        Cam7.saved_camstate_index = null;
    }
}

fn SaveSavedCam() void {
    if (Cam7.saved_camstate_index != null) return;
    Cam7.saved_camstate_index = mem.read(camstate_ref_addr, u32);

    const mat4_addr: u32 = rc.CAM_CAMSTATE_ARRAY_ADDR +
        Cam7.saved_camstate_index.? * rc.CAM_CAMSTATE_ITEM_SIZE + 0x14;
    @memcpy(@as(*[16]f32, @ptrCast(&Cam7.cam_mat4x4[0])), @as([*]f32, @ptrFromInt(mat4_addr)));
    Cam7.update_rot_from_cam(&Cam7.xcam_rot);
    @memcpy(@as(*[3]f32, @ptrCast(&Cam7.xcam_rot_target)), @as(*[3]f32, @ptrCast(&Cam7.xcam_rot)));

    _ = x86.mov_eax_imm32(0x453FA1, u32, 1); // map visual flags-related check
    var o = x86.mov_ecx_imm32(0x4539A0, u32, @as(u32, @bitCast(Cam7.fog_dist))); // fog dist, normal case
    _ = x86.nop_until(o, 0x4539A6);
    _ = x86.mov_espoff_imm32(0x4539AC, 0x24, @as(u32, @bitCast(Cam7.fog_dist))); // fog dist, flags @0=1 case

    r.WriteEntityValue(.cMan, 0, 0x78, u32, 31);
    _ = mem.write(camstate_ref_addr, u32, 31);
}

fn HandleSettings(gf: *GlobalFn) callconv(.C) void {
    Cam7.enable = gf.SettingGetB("cam7", "enable") orelse false;
    Cam7.flip_look_x = gf.SettingGetB("cam7", "flip_look_x") orelse false;
    Cam7.flip_look_y = gf.SettingGetB("cam7", "flip_look_y") orelse false;
}

// STATE MACHINE

fn DoStateNone(gs: *GlobalSt, gf: *GlobalFn) CamState {
    _ = gf;
    _ = gs;
    if (Cam7.input_toggle.gets() == .JustOn and Cam7.enable) {
        SaveSavedCam();
        return .FreeCam;
    }
    return .None;
}

fn DoStateFreeCam(gs: *GlobalSt, gf: *GlobalFn) CamState {
    _ = gf;
    if (Cam7.input_toggle.gets() == .JustOn or !Cam7.enable) {
        RestoreSavedCam();
        return .None;
    }

    const _a_rx: f32 = if (Cam7.flip_look_x) -Cam7.input_look_x.getf() else Cam7.input_look_x.getf();
    const _a_ry: f32 = if (Cam7.flip_look_y) -Cam7.input_look_y.getf() else Cam7.input_look_y.getf();
    const _a_lx: f32 = Cam7.input_move_x.getf();
    const _a_ly: f32 = Cam7.input_move_y.getf();
    const _a_t: f32 = Cam7.input_move_z.getf();

    // rotation

    const a_r_mag: f32 = smooth2(@min(m.sqrt(_a_rx * _a_rx + _a_ry * _a_ry), 1));
    const a_r_ang: f32 = m.atan2(f32, _a_ry, _a_rx);
    const a_rx: f32 = if (m.fabs(_a_rx) > Cam7.dz) a_r_mag * m.cos(a_r_ang) else 0;
    const a_ry: f32 = if (m.fabs(_a_ry) > Cam7.dz) a_r_mag * m.sin(a_r_ang) else 0;

    Cam7.xcam_rotation.x = a_rx;
    Cam7.xcam_rotation.z = 0;
    Cam7.xcam_rotation.z = -a_ry;
    //if (Cam7.xcam_rotation.magnitude() > 1)
    //    Cam7.xcam_rotation = Cam7.xcam_rotation.normalize();
    //Cam7.xcam_rotation.damp(&Cam7.xcam_rotation_target, Cam7.rotation_damp, gs.dt_f);

    Cam7.xcam_rot.x += gs.dt_f * Cam7.rotation_speed / 360 * rot * Cam7.xcam_rotation.x;
    Cam7.xcam_rot.y += 0;
    Cam7.xcam_rot.z += gs.dt_f * Cam7.rotation_speed / 360 * rot * Cam7.xcam_rotation.z;
    //Cam7.xcam_rot.damp(&Cam7.xcam_rot_target, Cam7.rotation_damp, gs.dt_f);
    Cam7.update_cam_from_rot(&Cam7.xcam_rot);

    // motion

    // TODO: individual X, Y deadzone; rather than magnitude-based
    const a_l_mag: f32 = @min(m.sqrt(_a_lx * _a_lx + _a_ly * _a_ly), 1);
    const a_l_ang: f32 = m.atan2(f32, _a_ly, _a_lx);
    const a_lx: f32 = smooth2(a_l_mag) * m.cos(a_l_ang - Cam7.xcam_rot.x);
    const a_ly: f32 = smooth2(a_l_mag) * m.sin(a_l_ang - Cam7.xcam_rot.x);
    const a_t: f32 = if (m.fabs(_a_t) > Cam7.dz) smooth2(_a_t) else 0;

    Cam7.xcam_motion_target.x = if (a_l_mag > Cam7.dz) a_lx else 0;
    Cam7.xcam_motion_target.y = if (a_l_mag > Cam7.dz) a_ly else 0;
    Cam7.xcam_motion_target.z = a_t;
    //if (Cam7.xcam_motion_target.magnitude() > 1)
    //    Cam7.xcam_motion_target = Cam7.xcam_motion_target.normalize();

    Cam7.xcam_motion.damp(&Cam7.xcam_motion_target, Cam7.motion_damp, gs.dt_f);

    Cam7.cam_mat4x4[3][0] += gs.dt_f * Cam7.motion_speed_xy * Cam7.xcam_motion.x;
    Cam7.cam_mat4x4[3][1] += gs.dt_f * Cam7.motion_speed_xy * Cam7.xcam_motion.y;
    Cam7.cam_mat4x4[3][2] += gs.dt_f * Cam7.motion_speed_z * Cam7.xcam_motion.z;

    return .FreeCam;
}

fn UpdateState(gs: *GlobalSt, gv: *GlobalFn) void {
    CheckAndResetSavedCam();
    Cam7.cam_state = switch (Cam7.cam_state) {
        .None => DoStateNone(gs, gv),
        .FreeCam => DoStateFreeCam(gs, gv),
    };
}

// math

const rot: f32 = m.pi * 2;

// TODO: move
fn smooth2(scalar: f32) f32 {
    return m.fabs(scalar) * scalar;
}

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

export fn OnInit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gs;
    HandleSettings(gf);
}

export fn OnInitLate(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
    rf.swrCam_CamState_InitMainMat4(31, 1, @intFromPtr(&Cam7.cam_mat4x4), 0);
}

export fn OnDeinit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
    RestoreSavedCam();
    rf.swrCam_CamState_InitMainMat4(31, 0, 0, 0);
}

// HOOKS

export fn InputUpdateB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gs;
    Cam7.update_input(gf);
}

export fn OnSettingsLoad(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gs;
    HandleSettings(gf);
}

export fn EarlyEngineUpdateA(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    UpdateState(gs, gf);
}
