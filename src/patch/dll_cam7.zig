const Self = @This();

const std = @import("std");

const m = std.math;
const deg2rad = m.degreesToRadians;

const w32 = @import("zigwin32");
const POINT = w32.foundation.POINT;

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;

const debug = @import("core/Debug.zig");

const InputMap = @import("core/Input.zig").InputMap;
const ButtonInputMap = @import("core/Input.zig").ButtonInputMap;
const AxisInputMap = @import("core/Input.zig").AxisInputMap;

const rti = @import("racer").Time;
const rc = @import("racer").Camera;
const re = @import("racer").Entity;
const rg = @import("racer").Global;
const rm = @import("racer").Matrix;
const rv = @import("racer").Vector;
const rte = @import("racer").Text;

const st = @import("util/active_state.zig");
const nt = @import("util/normalized_transform.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// Named after Camera 7 in Trackmania

// FEATURES
// - free cam
// - usable both in race and in cantina
// - CONTROLS:      keyboard        xinput
//   toggle         0               Back
//   XY-move        WASD            L Stick
//   XY-rotate      Mouse or ↑↓→←   R Stick
//   Z-move up      Space           L Trigger
//   Z-move down    Shift           R Trigger
//   movement down  Q               LB
//   movement up    E               RB
//   rotation down  Z               LSB
//   rotation up    C               RSB
//   damping        X               Y               hold to edit movement/rotation
//                                                  damping instead of speed
// - SETTINGS:
//   enable                 bool
//   flip_look_x            bool
//   flip_look_y            bool
//   stick_deadzone_inner   f32     0.0..0.5
//   stick_deadzone_outer   f32     0.5..1.0
//   mouse_dpi              u32     reference for mouse sensitivity calculations;
//                                  does not change mouse
//   mouse_cm360            f32     physical centimeters of motion for one 360° rotation
//                                  if you don't know what that means, just treat
//                                  this value as a sensitivity scale

// FIXME: cam seems to not always correct itself upright when switching?
// TODO: controls = ???
//   - option: drone-style controls, including Z-rotate
//   - option: z-control moving along view axis rather than world axis
//   - dinput controls
//   - speed toggles; infinite accel toggle
//   - control mapping
// TODO: fog
// - option: disable fog entirely
// - option: fog dist
// TODO: settings for all of the above

const PLUGIN_NAME: [*:0]const u8 = "Cam7";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const CamState = enum(u32) {
    None,
    FreeCam,
};

const Cam7 = extern struct {
    // ini settings
    var enable: bool = false;
    var flip_look_x: bool = false;
    var flip_look_y: bool = false;
    var dz_i: f32 = 0.05; // 0.0..0.5
    var dz_o: f32 = 0.95; // 0.5..1.0
    var dz_range: f32 = 0.9; // derived
    var dz_fact: f32 = 1.0 / 0.9; // derived
    var input_mouse_dpi: f32 = 1600; // only needed for sens calc, does not set mouse dpi
    var input_mouse_cm360: f32 = 24; // real-world space per full rotation
    var input_mouse_sens: f32 = 15118.1; // derived; mouse units per full rotation

    const rot_damp_val = [_]?f32{ null, 36, 24, 12 };
    var rot_damp: ?f32 = null;
    var rot_damp_i: usize = 0;
    const rot_speed: f32 = 360;
    const motion_damp: f32 = 8;
    const motion_change_damp: f32 = 8;
    var motion_speed_i: usize = 3;
    const motion_speed_xy_val = [_]f32{ 250, 500, 1000, 2000, 4000, 8000, 16000 };
    var motion_speed_xy: f32 = 2000;
    var motion_speed_xy_target: f32 = 2000;
    const motion_speed_z_val = [_]f32{ 125, 250, 500, 1000, 2000, 4000, 8000 };
    var motion_speed_z: f32 = 1000;
    var motion_speed_z_target: f32 = 1000;
    const fog_dist: f32 = 7500;

    var cam_state: CamState = .None;
    var saved_camstate_index: ?u32 = null;
    var cam_mat4x4: rm.Mat4x4 = .{};
    var xcam_rot: rv.Vec3 = .{};
    var xcam_rot_target: rv.Vec3 = .{};
    var xcam_rotation: rv.Vec3 = .{};
    var xcam_rotation_target: rv.Vec3 = .{};
    var xcam_motion: rv.Vec3 = .{};
    var xcam_motion_target: rv.Vec3 = .{};

    var input_toggle_data = ButtonInputMap{ .kb = .@"0", .xi = .BACK };
    var input_look_x_data = AxisInputMap{ .kb_dec = .LEFT, .kb_inc = .RIGHT, .xi_inc = .StickRX, .kb_scale = 0.65 };
    var input_look_y_data = AxisInputMap{ .kb_dec = .DOWN, .kb_inc = .UP, .xi_inc = .StickRY, .kb_scale = 0.65 };
    var input_move_x_data = AxisInputMap{ .kb_dec = .A, .kb_inc = .D, .xi_inc = .StickLX };
    var input_move_y_data = AxisInputMap{ .kb_dec = .S, .kb_inc = .W, .xi_inc = .StickLY };
    var input_move_z_data = AxisInputMap{ .kb_dec = .SHIFT, .kb_inc = .SPACE, .xi_dec = .TriggerR, .xi_inc = .TriggerL };
    var input_speed_dec_data = ButtonInputMap{ .kb = .Q, .xi = .LEFT_SHOULDER };
    var input_speed_inc_data = ButtonInputMap{ .kb = .E, .xi = .RIGHT_SHOULDER };
    var input_rotation_dec_data = ButtonInputMap{ .kb = .Z, .xi = .LEFT_THUMB };
    var input_rotation_inc_data = ButtonInputMap{ .kb = .C, .xi = .RIGHT_THUMB };
    var input_damp_data = ButtonInputMap{ .kb = .X, .xi = .Y };
    var input_toggle = input_toggle_data.inputMap();
    var input_look_x = input_look_x_data.inputMap();
    var input_look_y = input_look_y_data.inputMap();
    var input_move_x = input_move_x_data.inputMap();
    var input_move_y = input_move_y_data.inputMap();
    var input_move_z = input_move_z_data.inputMap();
    var input_speed_dec = input_speed_dec_data.inputMap();
    var input_speed_inc = input_speed_inc_data.inputMap();
    var input_rotation_dec = input_rotation_dec_data.inputMap();
    var input_rotation_inc = input_rotation_inc_data.inputMap();
    var input_damp = input_damp_data.inputMap();
    var input_mouse_d_x: f32 = 0;
    var input_mouse_d_y: f32 = 0;

    // TODO: maybe normalizing XY stuff
    fn update_input(gf: *GlobalFn) void {
        input_toggle.update(gf);
        input_look_x.update(gf);
        input_look_y.update(gf);
        input_move_x.update(gf);
        input_move_y.update(gf);
        input_move_z.update(gf);
        input_speed_dec.update(gf);
        input_speed_inc.update(gf);
        input_rotation_dec.update(gf);
        input_rotation_inc.update(gf);
        input_damp.update(gf);
        if (cam_state == .FreeCam and rg.PAUSE_STATE.* == 0) {
            gf.InputLockMouse();
            // TODO: move to InputMap
            const mouse_d: POINT = gf.InputGetMouseDelta();
            input_mouse_d_x = @as(f32, @floatFromInt(mouse_d.x)) / input_mouse_sens;
            input_mouse_d_y = @as(f32, @floatFromInt(mouse_d.y)) / input_mouse_sens;
        }
    }

    // FIXME: quaternion stuff
    //var v2_xf: rm.Mat4x4 = .{};
    //var v2_rot: rv.Vec3 = .{};
    //var v2_quat: Quat = .{};
    //var v2_loc: rm.Location = .{};
};

const Quat = rv.Vec4;
const AxisAngle = rv.Vec4;

fn quat_mul(out: *Quat, in1: *const Quat, in2: *const Quat) void {
    out.* = .{
        .x = in1.w * in2.x + in1.x * in2.w + in1.y * in2.z - in1.z * in2.y,
        .y = in1.w * in2.y + in1.y * in2.w + in1.z * in2.x - in1.x * in2.z,
        .z = in1.w * in2.z + in1.z * in2.w + in1.x * in2.y - in1.y * in2.x,
        .w = in1.w * in2.w - in1.x * in2.x - in1.y * in2.y - in1.z * in2.z,
    };
}

// axis-angle def
fn quat_setAA(out: *Quat, in: *const AxisAngle) void {
    std.debug.assert(1 == rv.Vec3_Magnitude(@ptrCast(in)));

    out.x = in.x * @sin(in.w);
    out.y = in.y * @sin(in.w);
    out.z = in.z * @sin(in.w);
    out.w = @cos(in.w);
}

fn quat_getAA(in: *const Quat, out: *AxisAngle) void {
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

fn mat4x4_getQuaternion(in: *const rm.Mat4x4, out: *Quat) void {
    out.w = m.sqrt(1.0 + in.X.x + in.Y.y + in.Z.z) / 2;
    const w4: f32 = 4 * out.w;
    out.x = (in.Z.y - in.Y.z) / w4;
    out.y = (in.X.z - in.Z.x) / w4;
    out.z = (in.Y.x - in.X.y) / w4;
}

// adapted from rm.Mat4x4_InitQuat
fn mat4x4_setQuaternion(out: *rm.Mat4x4, in: *const Quat) void {
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

fn mat4x4_getEuler(mat: *const rm.Mat4x4, euler: *rv.Vec3) void {
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

inline fn f32_damp(from: f32, to: f32, t: f32, dt: f32) f32 {
    if (m.fabs(to - from) < m.floatEps(f32)) return to;
    return std.math.lerp(from, to, 1 - std.math.exp(-t * dt));
}

inline fn vec3_damp(out: *rv.Vec3, in: *const rv.Vec3, t: f32, dt: f32) void {
    out.x = f32_damp(out.x, in.x, t, dt);
    out.y = f32_damp(out.y, in.y, t, dt);
    out.z = f32_damp(out.z, in.z, t, dt);
}

// TODO: testing, e.g. 0.05..0.95 (0.35) -> mag 0.333..
inline fn f32_applyDeadzone(out: *f32) void {
    const mag: f32 = @fabs(out.*);

    if (mag <= Cam7.dz_i) {
        out.* = 0;
        return;
    }

    const scale: f32 = if (mag >= Cam7.dz_o) (Cam7.dz_range / mag * Cam7.dz_fact) else ((mag - Cam7.dz_i) / Cam7.dz_range / mag);
    out.* *= scale;
}

// TODO: testing, e.g. 0.05..0.95 (0.35) -> mag 0.333..
inline fn vec2_applyDeadzone(out: *rv.Vec2) void {
    const mag: f32 = rv.Vec2_Mag(out);

    if (mag <= Cam7.dz_i) {
        out.* = .{ .x = 0, .y = 0 };
        return;
    }

    const scale: f32 = if (mag >= Cam7.dz_o) (Cam7.dz_range / mag * Cam7.dz_fact) else ((mag - Cam7.dz_i) / Cam7.dz_range / mag);
    rv.Vec2_Scale(out, scale, out);
}

const camstate_ref_addr: u32 = rc.METACAM_ARRAY_ADDR + 0x170; // = metacam index 1 0x04

inline fn CamTransitionOut() void {
    _ = x86.mov_eax_moffs32(0x453FA1, 0x50CA3C); // map visual flags-related check
    _ = x86.mov_ecx_u32(0x4539A0, 0x2D8); // fog dist, normal case
    _ = x86.mov_espoff_imm32(0x4539AC, 0x24, 0xBF800000); // fog dist, flags @0=1 case (-1.0)
    Cam7.xcam_motion_target = .{};
    Cam7.xcam_motion = .{};
    Cam7.saved_camstate_index = null;
}

fn CheckAndResetSavedCam() void {
    if (Cam7.saved_camstate_index == null) return;
    if (mem.read(camstate_ref_addr, u32) == 31) return;

    re.Manager.entity(.cMan, 0).CamStateIndex = 7;
    CamTransitionOut();
    Cam7.cam_state = .None;
}

fn RestoreSavedCam() void {
    if (Cam7.saved_camstate_index) |i| {
        _ = mem.write(camstate_ref_addr, u32, i);
        re.Manager.entity(.cMan, 0).CamStateIndex = i;
        CamTransitionOut();
    }
}

fn SaveSavedCam() void {
    if (Cam7.saved_camstate_index != null) return;
    Cam7.saved_camstate_index = mem.read(camstate_ref_addr, u32);

    const mat4_addr: u32 = rc.CAMSTATE_ARRAY_ADDR +
        Cam7.saved_camstate_index.? * rc.CAMSTATE_ITEM_SIZE + 0x14;
    @memcpy(@as(*[16]f32, @ptrCast(&Cam7.cam_mat4x4)), @as([*]f32, @ptrFromInt(mat4_addr)));
    mat4x4_getEuler(&Cam7.cam_mat4x4, &Cam7.xcam_rot);
    @memcpy(@as(*[3]f32, @ptrCast(&Cam7.xcam_rot_target)), @as(*[3]f32, @ptrCast(&Cam7.xcam_rot)));
    // FIXME: new, quaternion stuff
    //mat4x4_getQuaternion(@ptrFromInt(mat4_addr), &Cam7.v2_quat);
    //rm.Mat4x4_GetLocation(@ptrFromInt(mat4_addr), &Cam7.v2_loc);

    _ = x86.mov_eax_imm32(0x453FA1, u32, 1); // map visual flags-related check
    var o = x86.mov_ecx_imm32(0x4539A0, u32, @as(u32, @bitCast(Cam7.fog_dist))); // fog dist, normal case
    _ = x86.nop_until(o, 0x4539A6);
    _ = x86.mov_espoff_imm32(0x4539AC, 0x24, @as(u32, @bitCast(Cam7.fog_dist))); // fog dist, flags @0=1 case

    re.Manager.entity(.cMan, 0).CamStateIndex = 31;
    _ = mem.write(camstate_ref_addr, u32, 31);
}

fn HandleSettings(gf: *GlobalFn) callconv(.C) void {
    Cam7.enable = gf.SettingGetB("cam7", "enable") orelse false;

    Cam7.flip_look_x = gf.SettingGetB("cam7", "flip_look_x") orelse false;
    Cam7.flip_look_y = gf.SettingGetB("cam7", "flip_look_y") orelse false;

    Cam7.input_mouse_dpi = @floatFromInt(gf.SettingGetU("cam7", "mouse_dpi") orelse 1600);
    Cam7.input_mouse_cm360 = gf.SettingGetF("cam7", "mouse_cm360") orelse 24;
    Cam7.input_mouse_sens = Cam7.input_mouse_cm360 / 2.54 * Cam7.input_mouse_dpi;

    // TODO: more sophisticated range limiting that allows for more freedom?
    Cam7.dz_i = m.clamp(gf.SettingGetF("cam7", "stick_deadzone_inner") orelse 0.05, 0.000, 0.495);
    Cam7.dz_o = m.clamp(gf.SettingGetF("cam7", "stick_deadzone_outer") orelse 0.95, 0.505, 1.000);
    Cam7.dz_range = Cam7.dz_o - Cam7.dz_i;
    Cam7.dz_fact = 1 / Cam7.dz_range;
}

// STATE MACHINE

fn DoStateNone(_: *GlobalSt, _: *GlobalFn) CamState {
    if (Cam7.input_toggle.gets() == .JustOn and Cam7.enable) {
        SaveSavedCam();
        return .FreeCam;
    }
    return .None;
}

fn DoStateFreeCam(gs: *GlobalSt, _: *GlobalFn) CamState {
    if (Cam7.input_toggle.gets() == .JustOn or !Cam7.enable) {
        RestoreSavedCam();
        return .None;
    }

    // input

    if (Cam7.input_speed_dec.gets() == .JustOn and Cam7.motion_speed_i > 0)
        Cam7.motion_speed_i -= 1;
    if (Cam7.input_speed_inc.gets() == .JustOn and Cam7.motion_speed_i < 6)
        Cam7.motion_speed_i += 1;
    Cam7.motion_speed_xy_target = Cam7.motion_speed_xy_val[Cam7.motion_speed_i];
    Cam7.motion_speed_z_target = Cam7.motion_speed_z_val[Cam7.motion_speed_i];
    Cam7.motion_speed_xy = f32_damp(Cam7.motion_speed_xy, Cam7.motion_speed_xy_target, Cam7.motion_change_damp, gs.dt_f);
    Cam7.motion_speed_z = f32_damp(Cam7.motion_speed_z, Cam7.motion_speed_z_target, Cam7.motion_change_damp, gs.dt_f);

    if (Cam7.input_damp.gets().on()) {
        if (Cam7.input_rotation_dec.gets() == .JustOn and Cam7.rot_damp_i > 0)
            Cam7.rot_damp_i -= 1;
        if (Cam7.input_rotation_inc.gets() == .JustOn and Cam7.rot_damp_i < 3)
            Cam7.rot_damp_i += 1;
        Cam7.rot_damp = Cam7.rot_damp_val[Cam7.rot_damp_i];
    }

    // rotation

    var rot_scale: f32 = undefined;
    const using_mouse: bool = Cam7.input_mouse_d_x != 0 or Cam7.input_mouse_d_y != 0;
    if (using_mouse) {
        Cam7.xcam_rotation.x = if (Cam7.flip_look_x) Cam7.input_mouse_d_x else -Cam7.input_mouse_d_x;
        Cam7.xcam_rotation.y = if (Cam7.flip_look_y) Cam7.input_mouse_d_y else -Cam7.input_mouse_d_y;
        rot_scale = rot;
    } else {
        Cam7.xcam_rotation.x = if (Cam7.flip_look_x) Cam7.input_look_x.getf() else -Cam7.input_look_x.getf();
        Cam7.xcam_rotation.y = if (Cam7.flip_look_y) -Cam7.input_look_y.getf() else Cam7.input_look_y.getf();
        vec2_applyDeadzone(@ptrCast(&Cam7.xcam_rotation));
        const r_scale: f32 = nt.smooth2(rv.Vec2_Mag(@ptrCast(&Cam7.xcam_rotation)));
        rv.Vec2_Scale(@ptrCast(&Cam7.xcam_rotation), r_scale, @ptrCast(&Cam7.xcam_rotation));
        rot_scale = gs.dt_f * Cam7.rot_speed / 360 * rot;
    }
    Cam7.xcam_rotation.z = 0;

    if (!using_mouse and Cam7.rot_damp != null) {
        vec3_damp(&Cam7.xcam_rotation_target, &Cam7.xcam_rotation, Cam7.rot_damp.?, gs.dt_f);
        rv.Vec3_AddScale1(&Cam7.xcam_rot, &Cam7.xcam_rot, rot_scale, &Cam7.xcam_rotation_target);
    } else {
        rv.Vec3_AddScale1(&Cam7.xcam_rot, &Cam7.xcam_rot, rot_scale, &Cam7.xcam_rotation);
    }

    rm.Mat4x4_SetRotation(
        @ptrCast(&Cam7.cam_mat4x4),
        m.radiansToDegrees(f32, Cam7.xcam_rot.x),
        m.radiansToDegrees(f32, Cam7.xcam_rot.y),
        m.radiansToDegrees(f32, Cam7.xcam_rot.z),
    );

    // motion

    Cam7.xcam_motion_target.x = Cam7.input_move_x.getf();
    Cam7.xcam_motion_target.y = Cam7.input_move_y.getf();
    vec2_applyDeadzone(@ptrCast(&Cam7.xcam_motion_target));
    const l_scale: f32 = nt.pow4(rv.Vec2_Mag(@ptrCast(&Cam7.xcam_motion_target)));
    const l_ang: f32 = m.atan2(f32, Cam7.xcam_motion_target.y, Cam7.xcam_motion_target.x) + Cam7.xcam_rot.x;
    Cam7.xcam_motion_target.x = l_scale * m.cos(l_ang);
    Cam7.xcam_motion_target.y = l_scale * m.sin(l_ang);

    Cam7.xcam_motion_target.z = Cam7.input_move_z.getf();
    f32_applyDeadzone(&Cam7.xcam_motion_target.z);
    Cam7.xcam_motion_target.z = nt.smooth4(Cam7.xcam_motion_target.z);

    vec3_damp(&Cam7.xcam_motion, &Cam7.xcam_motion_target, Cam7.motion_damp, gs.dt_f);

    Cam7.cam_mat4x4.T.x += gs.dt_f * Cam7.motion_speed_xy * Cam7.xcam_motion.x;
    Cam7.cam_mat4x4.T.y += gs.dt_f * Cam7.motion_speed_xy * Cam7.xcam_motion.y;
    Cam7.cam_mat4x4.T.z += gs.dt_f * Cam7.motion_speed_z * Cam7.xcam_motion.z;

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

//// TODO: move to lib, or replace with real lib
//const Vec3 = extern struct {
//    x: f32,
//    y: f32,
//    z: f32,
//
//
//};
//
//// TODO: move to vec lib, or find glm equivalent
//fn mmul(comptime n: u32, in1: *[n][n]f32, in2: *[n][n]f32, out: *[n][n]f32) void {
//    inline for (0..n) |i| {
//        inline for (0..n) |j| {
//            var v: f32 = 0;
//            inline for (0..n) |k| v += in1[i][k] * in2[k][j];
//            out[i][j] = v;
//        }
//    }
//}

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

export fn OnInit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    HandleSettings(gf);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    rc.swrCam_CamState_InitMainMat4(31, 1, @intFromPtr(&Cam7.cam_mat4x4), 0);
    // FIXME: quaternion stuff
    //rc.swrCam_CamState_InitMainMat4(31, 1, @intFromPtr(&Cam7.v2_xf), 0);
}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    RestoreSavedCam();
    rc.swrCam_CamState_InitMainMat4(31, 0, 0, 0);
}

// HOOKS

export fn InputUpdateB(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    Cam7.update_input(gf);
}

export fn OnSettingsLoad(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    HandleSettings(gf);
}

export fn EngineUpdateStage20A(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    UpdateState(gs, gf);
}
