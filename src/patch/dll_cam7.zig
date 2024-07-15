const Self = @This();

const std = @import("std");

const m = std.math;
const deg2rad = m.degreesToRadians;
const rad2deg = m.radiansToDegrees;

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
const rs = @import("racer").Sound;
const re = @import("racer").Entity;
const rg = @import("racer").Global;
const rm = @import("racer").Matrix;
const rv = @import("racer").Vector;
const rte = @import("racer").Text;
const rmo = @import("racer").Model;
const rin = @import("racer").Input;
const Vec2 = rv.Vec2;
const Vec3 = rv.Vec3;
const Vec4 = rv.Vec4;
const Mat4x4 = rm.Mat4x4;

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
// - CONTROLS:                  keyboard        xinput
//   toggle                     0               Back
//   XY-move                    WASD            L Stick
//   XY-rotate                  Mouse or ↑↓→←   R Stick
//   Z-move up                  Space           L Trigger
//   Z-move down                Shift           R Trigger
//   movement down              Q               LB
//   movement up                E               RB          up+down = return to default
//   rotation down              Z               LSB
//   rotation up                C               RSB         up+down = return to default
//   damping                    X               Y           hold to edit movement/rotation
//                                                          damping instead of speed
//   toggle planar movement     Tab             B
//   toggle hide ui             6
//   toggle disable input       7                           pod will not drive when on
//   pan and orbit mode         RCtrl           X           hold
//   move pod to camera         Bksp            A           hold while exiting free-cam
// - SETTINGS:
//   enable                     bool
//   fog_patch                  bool
//   fog_remove                 bool
//   visuals_patch              bool
//   sfx_vol                    f32     0.0..1.0
//   flip_look_x                bool
//   flip_look_y                bool
//   flip_look_x_inverted       bool
//   stick_deadzone_inner       f32     0.0..0.5
//   stick_deadzone_outer       f32     0.5..1.0
//   default_move_speed         u32     0..6
//   default_move_smoothing     u32     0..3
//   default_rotation_speed     u32     0..4
//   default_rotation_smoothing u32     0..3
//   default_planar_movement    bool    level motion vs view angle-based motion
//   default_hide_ui            bool
//   default_disable_input      bool
//   mouse_dpi                  u32     reference for mouse sensitivity calculations;
//                                      does not change mouse
//   mouse_cm360                f32     physical centimeters of motion for one 360° rotation
//                                      if you don't know what that means, just treat
//                                      this value as a sensitivity scale

// TODO: controls = ???
//   - option: drone-style controls, including Z-rotate
//   - dinput controls
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
    var flip_look_x_inverted: bool = true;
    var dz_i: f32 = 0.05; // 0.0..0.5
    var dz_o: f32 = 0.95; // 0.5..1.0
    var dz_range: f32 = 0.9; // derived
    var dz_fact: f32 = 1.0 / 0.9; // derived
    var input_mouse_dpi: f32 = 1600; // only needed for sens calc, does not set mouse dpi
    var input_mouse_cm360: f32 = 24; // real-world space per full rotation
    var input_mouse_sens: f32 = 15118.1; // derived; mouse units per full rotation
    var rot_damp_i_dflt: usize = 0;
    var rot_spd_i_dflt: usize = 3;
    var move_damp_i_dflt: usize = 2;
    var move_spd_i_dflt: usize = 3;
    var rot_damp_i: usize = 0;
    var rot_spd_i: usize = 3;
    var move_damp_i: usize = 2;
    var move_spd_i: usize = 3;
    var move_planar: bool = false;
    var hide_ui: bool = false;
    var disable_input: bool = false;
    var sfx_volume: f32 = 0.7;
    var sfx_volume_scale: f32 = 0; // derived
    var fog_patch: bool = true;
    var fog_remove: bool = false;
    var visuals_patch: bool = true;

    const rot_damp_val = [_]?f32{ null, 36, 24, 12, 6 };
    var rot_damp: ?f32 = null;
    const rot_spd_val = [_]f32{ 80, 160, 240, 360, 540, 810 };
    const rot_change_damp: f32 = 8;
    var rot_spd: f32 = 360;
    var rot_spd_tgt: f32 = 360;
    var orbit_dist: f32 = 0;
    var orbit_dist_delta: f32 = 0;
    var orbit_pos: Vec3 = .{};

    const move_damp_val = [_]?f32{ null, 16, 8, 4 };
    var move_damp: ?f32 = 8;
    const move_change_damp: f32 = 8;
    const move_spd_xy_val = [_]f32{ 125, 250, 500, 1000, 2000, 4000, 8000, 16000 };
    var move_spd_xy: f32 = 1000;
    var move_spd_xy_tgt: f32 = 1000;
    const move_spd_z_val = [_]f32{ 62.5, 125, 250, 500, 1000, 2000, 4000, 8000 };
    var move_spd_z: f32 = 500;
    var move_spd_z_tgt: f32 = 500;

    const fog_dist: f32 = 7500;

    var cam_state: CamState = .None;
    var saved_camstate_index: ?u32 = null;
    var xf: Mat4x4 = .{};
    var xf_look: Mat4x4 = .{};
    var xcam_rot: Vec3 = .{}; // overall
    var xcam_rotation: Vec3 = .{}; // per-frame offset
    var xcam_rotation_tgt: Vec3 = .{};
    var xcam_motion: Vec3 = .{};
    var xcam_motion_tgt: Vec3 = .{};

    var dir_right: Vec3 = .{};
    var dir_forward: Vec3 = .{};
    var dir_up: Vec3 = .{};

    var input_toggle_data = ButtonInputMap{ .kb = .@"0", .xi = .BACK };
    var input_look_x_data = AxisInputMap{ .kb_dec = .LEFT, .kb_inc = .RIGHT, .xi_inc = .StickRX };
    var input_look_y_data = AxisInputMap{ .kb_dec = .DOWN, .kb_inc = .UP, .xi_inc = .StickRY };
    var input_move_x_data = AxisInputMap{ .kb_dec = .A, .kb_inc = .D, .xi_inc = .StickLX };
    var input_move_y_data = AxisInputMap{ .kb_dec = .S, .kb_inc = .W, .xi_inc = .StickLY };
    var input_move_z_data = AxisInputMap{ .kb_dec = .SHIFT, .kb_inc = .SPACE, .xi_dec = .TriggerR, .xi_inc = .TriggerL };
    var input_movement_dec_data = ButtonInputMap{ .kb = .Q, .xi = .LEFT_SHOULDER };
    var input_movement_inc_data = ButtonInputMap{ .kb = .E, .xi = .RIGHT_SHOULDER };
    var input_rotation_dec_data = ButtonInputMap{ .kb = .Z, .xi = .LEFT_THUMB };
    var input_rotation_inc_data = ButtonInputMap{ .kb = .C, .xi = .RIGHT_THUMB };
    var input_damp_data = ButtonInputMap{ .kb = .X, .xi = .Y };
    var input_planar_data = ButtonInputMap{ .kb = .TAB, .xi = .B };
    var input_sweep_data = ButtonInputMap{ .kb = .RCONTROL, .xi = .X };
    //var input_mpan_data = ButtonInputMap{ .kb = .LBUTTON };
    //var input_morbit_data = ButtonInputMap{ .kb = .RBUTTON };
    var input_hide_ui_data = ButtonInputMap{ .kb = .@"6" };
    var input_disable_input_data = ButtonInputMap{ .kb = .@"7" };
    var input_move_vehicle_data = ButtonInputMap{ .kb = .BACK, .xi = .A };
    var input_toggle = input_toggle_data.inputMap();
    var input_look_x = input_look_x_data.inputMap();
    var input_look_y = input_look_y_data.inputMap();
    var input_move_x = input_move_x_data.inputMap();
    var input_move_y = input_move_y_data.inputMap();
    var input_move_z = input_move_z_data.inputMap();
    var input_movement_dec = input_movement_dec_data.inputMap();
    var input_movement_inc = input_movement_inc_data.inputMap();
    var input_rotation_dec = input_rotation_dec_data.inputMap();
    var input_rotation_inc = input_rotation_inc_data.inputMap();
    var input_damp = input_damp_data.inputMap();
    var input_planar = input_planar_data.inputMap();
    var input_sweep = input_sweep_data.inputMap();
    var input_hide_ui = input_hide_ui_data.inputMap();
    var input_disable_input = input_disable_input_data.inputMap();
    var input_move_vehicle = input_move_vehicle_data.inputMap();
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
        input_movement_dec.update(gf);
        input_movement_inc.update(gf);
        input_rotation_dec.update(gf);
        input_rotation_inc.update(gf);
        input_damp.update(gf);
        input_planar.update(gf);
        input_sweep.update(gf);
        input_hide_ui.update(gf);
        input_disable_input.update(gf);
        input_move_vehicle.update(gf);

        if (cam_state == .FreeCam and rg.PAUSE_STATE.* == 0) {
            gf.InputLockMouse();
            // TODO: move to InputMap
            const mouse_d: POINT = gf.InputGetMouseDelta();
            input_mouse_d_x = @as(f32, @floatFromInt(mouse_d.x)) / input_mouse_sens;
            input_mouse_d_y = @as(f32, @floatFromInt(mouse_d.y)) / input_mouse_sens;
        }
    }

    // FIXME: quaternion stuff
    //var v2_xf: Mat4x4 = .{};
    //var v2_rot: Vec3 = .{};
    //var v2_quat: Quat = .{};
    //var v2_loc: rm.Location = .{};
};

const Quat = Vec4;
const AxisAngle = Vec4;

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

fn mat4x4_getQuaternion(in: *const Mat4x4, out: *Quat) void {
    out.w = m.sqrt(1.0 + in.X.x + in.Y.y + in.Z.z) / 2;
    const w4: f32 = 4 * out.w;
    out.x = (in.Z.y - in.Y.z) / w4;
    out.y = (in.X.z - in.Z.x) / w4;
    out.z = (in.Y.x - in.X.y) / w4;
}

// adapted from Mat4x4_InitQuat
fn mat4x4_setQuaternion(out: *Mat4x4, in: *const Quat) void {
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

fn mat4x4_getEuler(mat: *const Mat4x4, euler: *Vec3) void {
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

fn mat4x4_getRow(in: *const Mat4x4, out: *Vec3, row: usize) void {
    const _in: *const [4][4]f32 = @ptrCast(in);
    out.x = _in[0][row];
    out.y = _in[1][row];
    out.z = _in[2][row];
}

fn mat4x4_setRotation(out: *Mat4x4, in: *const Vec3) void {
    rm.Mat4x4_SetRotation(out, rad2deg(f32, in.x), rad2deg(f32, in.y), rad2deg(f32, in.z));
}

inline fn vec3_mul3(out: *Vec3, x: f32, y: f32, z: f32) void {
    out.x *= x;
    out.y *= y;
    out.z *= z;
}

inline fn vec3_damp(out: *Vec3, in: *const Vec3, t: f32, dt: f32) void {
    out.x = f32_damp(out.x, in.x, t, dt);
    out.y = f32_damp(out.y, in.y, t, dt);
    out.z = f32_damp(out.z, in.z, t, dt);
}

inline fn f32_damp(from: f32, to: f32, t: f32, dt: f32) f32 {
    if (m.fabs(to - from) < m.floatEps(f32)) return to;
    return std.math.lerp(from, to, 1 - std.math.exp(-t * dt));
}

// TODO: testing, e.g. 0.05..0.95 (0.35) -> mag 0.333..
inline fn vec2_applyDeadzone(out: *Vec2) void {
    const mag: f32 = rv.Vec2_Mag(out);

    if (mag <= Cam7.dz_i) {
        out.* = .{ .x = 0, .y = 0 };
        return;
    }

    const scale: f32 = if (mag >= Cam7.dz_o) (Cam7.dz_range / mag * Cam7.dz_fact) else ((mag - Cam7.dz_i) / Cam7.dz_range / mag);
    rv.Vec2_Scale(out, scale, out);
}

// TODO: testing, e.g. 0.05..0.95 (0.35) -> mag 0.333..
// sm64-style deadzone
inline fn vec2_applyDeadzoneSq(out: *Vec2) void {
    out.x = if (@fabs(out.x) < Cam7.dz_i) 0 else out.x - -m.sign(out.x) * Cam7.dz_i;
    out.y = if (@fabs(out.y) < Cam7.dz_i) 0 else out.y - -m.sign(out.y) * Cam7.dz_i;
    if (out.x == 0 and out.y == 0) return;

    const mag: f32 = rv.Vec2_Mag(out);
    const scale: f32 = if (mag > Cam7.dz_range) Cam7.dz_range / mag else Cam7.dz_fact;
    rv.Vec2_Scale(out, scale, out);
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
// sm64-style deadzone
inline fn f32_applyDeadzoneSq(out: *f32) void {
    out.* = if (@fabs(out.*) < Cam7.dz_i) 0 else out.* - -m.sign(out.*) * Cam7.dz_i;
    if (out.* == 0) return;

    const mag: f32 = @fabs(out.*);
    out.* *= if (mag > Cam7.dz_range) Cam7.dz_range / mag else Cam7.dz_fact;
}

const camstate_ref_addr: u32 = rc.METACAM_ARRAY_ADDR + 0x170; // = metacam index 1 0x04

inline fn patchFlags(on: bool) void {
    if (on) {
        _ = x86.mov_eax_imm32(0x453FA1, u32, 1); // map visual flags-related check
    } else {
        _ = x86.mov_eax_moffs32(0x453FA1, 0x50CA3C); // map visual flags-related check
    }
}

inline fn patchFog(on: bool) void {
    if (on) {
        const dist = if (Cam7.fog_remove) comptime m.pow(f32, 10, 10) else Cam7.fog_dist;
        var o = x86.mov_ecx_imm32(0x4539A0, u32, @as(u32, @bitCast(dist))); // fog dist, normal case
        _ = x86.nop_until(o, 0x4539A6);
        _ = x86.mov_espoff_imm32(0x4539AC, 0x24, @bitCast(dist)); // fog dist, flags @0=1 case
        return;
    }
    _ = x86.mov_ecx_u32(0x4539A0, 0x2D8); // fog dist, normal case
    _ = x86.mov_espoff_imm32(0x4539AC, 0x24, 0xBF800000); // fog dist, flags @0=1 case (-1.0)
}

inline fn CamTransitionOut() void {
    patchFlags(false);
    patchFog(false);
    Cam7.xcam_motion_tgt = .{};
    Cam7.xcam_motion = .{};
    Cam7.saved_camstate_index = null;
}

fn SaveSavedCam() void {
    if (Cam7.saved_camstate_index != null) return;
    Cam7.saved_camstate_index = mem.read(camstate_ref_addr, u32);

    const mat4_addr: u32 = rc.CAMSTATE_ARRAY_ADDR +
        Cam7.saved_camstate_index.? * rc.CAMSTATE_ITEM_SIZE + 0x14;
    @memcpy(@as(*[16]f32, @ptrCast(&Cam7.xf)), @as([*]f32, @ptrFromInt(mat4_addr)));
    mat4x4_getEuler(&Cam7.xf, &Cam7.xcam_rot);
    // FIXME: new, quaternion stuff
    //mat4x4_getQuaternion(@ptrFromInt(mat4_addr), &Cam7.v2_quat);
    //rm.Mat4x4_GetLocation(@ptrFromInt(mat4_addr), &Cam7.v2_loc);

    patchFlags(Cam7.visuals_patch);
    patchFog(Cam7.fog_patch);

    re.Manager.entity(.cMan, 0).CamStateIndex = 31;
    _ = mem.write(camstate_ref_addr, u32, 31);
}

fn RestoreSavedCam() void {
    if (Cam7.saved_camstate_index) |i| {
        _ = mem.write(camstate_ref_addr, u32, i);
        re.Manager.entity(.cMan, 0).CamStateIndex = i;
        CamTransitionOut();
    }
}

fn CheckAndResetSavedCam(gf: *GlobalFn) void {
    if (Cam7.saved_camstate_index == null) return;
    if (mem.read(camstate_ref_addr, u32) == 31) return;

    re.Manager.entity(.cMan, 0).CamStateIndex = 7;
    CamTransitionOut();
    Cam7.cam_state = .None;
    _ = gf.GameHideRaceUIDisable(PLUGIN_NAME);
}

fn HandleSettings(gf: *GlobalFn) callconv(.C) void {
    Cam7.enable = gf.SettingGetB("cam7", "enable") orelse false;

    Cam7.fog_patch = gf.SettingGetB("cam7", "fog_patch") orelse true;
    Cam7.fog_remove = gf.SettingGetB("cam7", "fog_remove") orelse false;
    Cam7.visuals_patch = gf.SettingGetB("cam7", "visuals_patch") orelse true;
    if (Cam7.cam_state == .FreeCam) {
        patchFog(Cam7.fog_patch);
        patchFlags(Cam7.visuals_patch);
    }

    Cam7.flip_look_x = gf.SettingGetB("cam7", "flip_look_x") orelse false;
    Cam7.flip_look_y = gf.SettingGetB("cam7", "flip_look_y") orelse false;
    Cam7.flip_look_x_inverted = gf.SettingGetB("cam7", "flip_look_x_inverted") orelse false;

    Cam7.input_mouse_dpi = @floatFromInt(gf.SettingGetU("cam7", "mouse_dpi") orelse 1600);
    Cam7.input_mouse_cm360 = gf.SettingGetF("cam7", "mouse_cm360") orelse 24;
    Cam7.input_mouse_sens = Cam7.input_mouse_cm360 / 2.54 * Cam7.input_mouse_dpi;

    // TODO: more sophisticated range limiting that allows for more freedom?
    Cam7.dz_i = m.clamp(gf.SettingGetF("cam7", "stick_deadzone_inner") orelse 0.05, 0.000, 0.495);
    Cam7.dz_o = m.clamp(gf.SettingGetF("cam7", "stick_deadzone_outer") orelse 0.95, 0.505, 1.000);
    Cam7.dz_range = Cam7.dz_o - Cam7.dz_i;
    Cam7.dz_fact = 1 / Cam7.dz_range;

    // TODO: keep settings file in sync with these, to remember between sessions (after settings rework)
    Cam7.move_planar = gf.SettingGetB("cam7", "default_planar_movement") orelse false;
    Cam7.rot_damp_i = m.clamp(gf.SettingGetU("cam7", "default_rotation_smoothing") orelse 0, 0, 4);
    Cam7.rot_damp_i_dflt = Cam7.rot_damp_i;
    Cam7.rot_damp = Cam7.rot_damp_val[Cam7.rot_damp_i];
    Cam7.rot_spd_i = m.clamp(gf.SettingGetU("cam7", "default_rotation_speed") orelse 3, 0, 5);
    Cam7.rot_spd_i_dflt = Cam7.rot_spd_i;
    Cam7.rot_spd_tgt = Cam7.rot_spd_val[Cam7.rot_spd_i];
    Cam7.move_damp_i = m.clamp(gf.SettingGetU("cam7", "default_move_smoothing") orelse 2, 0, 3);
    Cam7.move_damp_i_dflt = Cam7.move_damp_i;
    Cam7.move_damp = Cam7.move_damp_val[Cam7.move_damp_i];
    Cam7.move_spd_i = m.clamp(gf.SettingGetU("cam7", "default_move_speed") orelse 3, 0, 6);
    Cam7.move_spd_i_dflt = Cam7.move_spd_i;
    Cam7.move_spd_xy_tgt = Cam7.move_spd_xy_val[Cam7.move_spd_i];
    Cam7.move_spd_z_tgt = Cam7.move_spd_z_val[Cam7.move_spd_i];

    Cam7.disable_input = gf.SettingGetB("cam7", "default_disable_input") orelse false;
    Cam7.hide_ui = gf.SettingGetB("cam7", "default_hide_ui") orelse false;
    UpdateHideUI(gf);

    Cam7.sfx_volume = m.clamp(gf.SettingGetF("cam7", "sfx_volume") orelse 0.7, 0, 1);
}

fn UpdateHideUI(gf: *GlobalFn) void {
    if (Cam7.hide_ui and Cam7.cam_state == .FreeCam) {
        _ = gf.GameHideRaceUIEnable(PLUGIN_NAME);
        return;
    }

    _ = gf.GameHideRaceUIDisable(PLUGIN_NAME);
}

// STATE MACHINE

fn DoStateNone(_: *GlobalSt, gf: *GlobalFn) CamState {
    if (Cam7.input_toggle.gets() == .JustOn and Cam7.enable) {
        SaveSavedCam();
        if (Cam7.hide_ui) _ = gf.GameHideRaceUIEnable(PLUGIN_NAME);
        return .FreeCam;
    }
    return .None;
}

fn DoStateFreeCam(gs: *GlobalSt, gf: *GlobalFn) CamState {
    if (Cam7.input_toggle.gets() == .JustOn or !Cam7.enable) {
        if (gs.race_state != .None and Cam7.input_move_vehicle.gets().on()) {
            re.Test.DoRespawn(re.Test.PLAYER.*, 0);
            re.Test.PLAYER.*._collision_toggles = 0xFFFFFFFF;
            re.Test.PLAYER.*.transform = Cam7.xf;
            var fwd: Vec3 = .{ .x = 0, .y = 11, .z = 0 };
            rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
            rv.Vec3_Add(@ptrCast(&re.Test.PLAYER.*.transform.T), @ptrCast(&re.Test.PLAYER.*.transform.T), &fwd);

            for (re.Manager.entitySliceAllObj(.cMan)) |*cman| {
                if (cman.pTest != null) {
                    const anim_mode = cman.mode;
                    cman.animTimer = 8;
                    re.cMan.DoPreRaceSweep(cman);
                    cman.mode = anim_mode;
                }
            }
        }

        RestoreSavedCam();
        _ = gf.GameHideRaceUIDisable(PLUGIN_NAME);
        return .None;
    }

    if (Cam7.input_hide_ui.gets() == .JustOn) {
        Cam7.hide_ui = !Cam7.hide_ui;
        UpdateHideUI(gf);
    }

    if (Cam7.input_disable_input.gets() == .JustOn)
        Cam7.disable_input = !Cam7.disable_input;

    // input

    if (Cam7.input_planar.gets() == .JustOn)
        Cam7.move_planar = !Cam7.move_planar;

    const move_sweep: bool = Cam7.input_sweep.gets().on();
    if (Cam7.input_sweep.gets() == .JustOn) {
        Cam7.orbit_dist = 200;
        Cam7.orbit_dist_delta = 0;
        var fwd: Vec3 = .{ .y = Cam7.orbit_dist };
        rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
        rv.Vec3_Add(&Cam7.orbit_pos, @ptrCast(&Cam7.xf.T), &fwd);
    }

    const move_dec: bool = Cam7.input_movement_dec.gets() == .JustOn;
    const move_inc: bool = Cam7.input_movement_inc.gets() == .JustOn;
    const move_both: bool = (move_dec and Cam7.input_movement_inc.gets().on()) or
        (move_inc and Cam7.input_movement_dec.gets().on());
    if (Cam7.input_damp.gets().on()) {
        if (move_dec and Cam7.move_damp_i > 0) Cam7.move_damp_i -= 1;
        if (move_inc and Cam7.move_damp_i < 3) Cam7.move_damp_i += 1;
        if (move_both) Cam7.move_damp_i = Cam7.move_damp_i_dflt;
        Cam7.move_damp = Cam7.move_damp_val[Cam7.move_damp_i];
    } else {
        if (move_dec and Cam7.move_spd_i > 0) Cam7.move_spd_i -= 1;
        if (move_inc and Cam7.move_spd_i < 7) Cam7.move_spd_i += 1;
        if (move_both) Cam7.move_spd_i = Cam7.move_spd_i_dflt;
        Cam7.move_spd_xy_tgt = Cam7.move_spd_xy_val[Cam7.move_spd_i];
        Cam7.move_spd_z_tgt = Cam7.move_spd_z_val[Cam7.move_spd_i];
    }
    Cam7.move_spd_xy = f32_damp(Cam7.move_spd_xy, Cam7.move_spd_xy_tgt, Cam7.move_change_damp, gs.dt_f);
    Cam7.move_spd_z = f32_damp(Cam7.move_spd_z, Cam7.move_spd_z_tgt, Cam7.move_change_damp, gs.dt_f);

    const rot_dec: bool = Cam7.input_rotation_dec.gets() == .JustOn;
    const rot_inc: bool = Cam7.input_rotation_inc.gets() == .JustOn;
    const rot_both: bool = (rot_dec and Cam7.input_rotation_inc.gets().on()) or
        (rot_inc and Cam7.input_rotation_dec.gets().on());
    if (Cam7.input_damp.gets().on()) {
        if (rot_dec and Cam7.rot_damp_i > 0) Cam7.rot_damp_i -= 1;
        if (rot_inc and Cam7.rot_damp_i < 4) Cam7.rot_damp_i += 1;
        if (rot_both) Cam7.rot_damp_i = Cam7.rot_damp_i_dflt;
        Cam7.rot_damp = Cam7.rot_damp_val[Cam7.rot_damp_i];
    } else {
        if (rot_dec and Cam7.rot_spd_i > 0) Cam7.rot_spd_i -= 1;
        if (rot_inc and Cam7.rot_spd_i < 5) Cam7.rot_spd_i += 1;
        if (rot_both) Cam7.rot_spd_i = Cam7.rot_spd_i_dflt;
        Cam7.rot_spd_tgt = Cam7.rot_spd_val[Cam7.rot_spd_i];
    }
    Cam7.rot_spd = f32_damp(Cam7.rot_spd, Cam7.rot_spd_tgt, Cam7.rot_change_damp, gs.dt_f);

    const upside_down: bool = @mod(Cam7.xcam_rot.y / rot - 0.25, 1) < 0.5;

    // rotation

    var rot_scale: f32 = undefined;
    const using_mouse: bool = Cam7.input_mouse_d_x != 0 or Cam7.input_mouse_d_y != 0;
    const flip_x: bool = Cam7.flip_look_x != (Cam7.flip_look_x_inverted and upside_down);
    if (using_mouse) {
        Cam7.xcam_rotation.x = if (flip_x) Cam7.input_mouse_d_x else -Cam7.input_mouse_d_x;
        Cam7.xcam_rotation.y = if (Cam7.flip_look_y) Cam7.input_mouse_d_y else -Cam7.input_mouse_d_y;
        rot_scale = rot;
    } else {
        Cam7.xcam_rotation.x = if (flip_x) Cam7.input_look_x.getf() else -Cam7.input_look_x.getf();
        Cam7.xcam_rotation.y = if (Cam7.flip_look_y) -Cam7.input_look_y.getf() else Cam7.input_look_y.getf();
        vec2_applyDeadzoneSq(@ptrCast(&Cam7.xcam_rotation));
        const r_scale: f32 = nt.smooth2(rv.Vec2_Mag(@ptrCast(&Cam7.xcam_rotation)));
        rv.Vec2_Scale(@ptrCast(&Cam7.xcam_rotation), r_scale, @ptrCast(&Cam7.xcam_rotation));
        rot_scale = gs.dt_f * Cam7.rot_spd / 360 * rot;
    }
    Cam7.xcam_rotation.z = 0;

    if (!using_mouse and Cam7.rot_damp != null) {
        vec3_damp(&Cam7.xcam_rotation_tgt, &Cam7.xcam_rotation, Cam7.rot_damp.?, gs.dt_f);
        rv.Vec3_AddScale1(&Cam7.xcam_rot, &Cam7.xcam_rot, rot_scale, &Cam7.xcam_rotation_tgt);
    } else {
        rv.Vec3_Copy(&Cam7.xcam_rotation_tgt, &Cam7.xcam_rotation);
        rv.Vec3_AddScale1(&Cam7.xcam_rot, &Cam7.xcam_rot, rot_scale, &Cam7.xcam_rotation);
    }
    Cam7.xcam_rot.z = f32_damp(Cam7.xcam_rot.z, 0, 16, gs.dt_f); // NOTE: straighten out, not needed for drone

    if (move_sweep) {
        var fwd: Vec3 = .{ .y = Cam7.orbit_dist };
        rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
        rv.Vec3_Add(&Cam7.orbit_pos, @ptrCast(&Cam7.xf.T), &fwd);
    }

    mat4x4_setRotation(&Cam7.xf, &Cam7.xcam_rot);

    if (move_sweep) {
        var fwd: Vec3 = .{ .y = Cam7.orbit_dist };
        rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
        rv.Vec3_Sub(@ptrCast(&Cam7.xf.T), &Cam7.orbit_pos, &fwd);
    }

    // motion

    var xf_ref: *Mat4x4 = &Cam7.xf;

    Cam7.xcam_motion_tgt.z = Cam7.input_move_z.getf();
    f32_applyDeadzoneSq(&Cam7.xcam_motion_tgt.z);
    Cam7.xcam_motion_tgt.z = nt.smooth4(Cam7.xcam_motion_tgt.z);

    Cam7.xcam_motion_tgt.x = Cam7.input_move_x.getf();
    Cam7.xcam_motion_tgt.y = Cam7.input_move_y.getf();
    vec2_applyDeadzoneSq(@ptrCast(&Cam7.xcam_motion_tgt));

    // TODO: state machine enum, probably
    if (move_sweep) {
        var orbit_dist_delta_target: f32 = Cam7.xcam_motion_tgt.z;
        Cam7.xcam_motion_tgt.z = Cam7.xcam_motion_tgt.y;
        vec3_mul3(&Cam7.xcam_motion_tgt, Cam7.move_spd_xy, 0, Cam7.move_spd_xy);

        Cam7.orbit_dist_delta = if (Cam7.move_damp) |d| f32_damp(Cam7.orbit_dist_delta, orbit_dist_delta_target, d, gs.dt_f) else orbit_dist_delta_target;
        var dist_delta: f32 = Cam7.orbit_dist_delta * Cam7.move_spd_z * gs.dt_f;
        if (Cam7.orbit_dist + dist_delta < 0) dist_delta = -Cam7.orbit_dist;
        var fwd: Vec3 = .{ .y = dist_delta };
        Cam7.orbit_dist += dist_delta;
        rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
        rv.Vec3_Sub(@ptrCast(&Cam7.xf.T), @ptrCast(&Cam7.xf.T), &fwd);
    } else if (Cam7.move_planar) {
        if (upside_down) {
            Cam7.xcam_motion_tgt.y *= -1.0;
            Cam7.xcam_motion_tgt.z *= -1.0;
        }
        vec3_mul3(&Cam7.xcam_motion_tgt, Cam7.move_spd_xy, Cam7.move_spd_xy, Cam7.move_spd_z);

        rm.Mat4x4_SetRotation(&Cam7.xf_look, rad2deg(f32, Cam7.xcam_rot.x), 0, rad2deg(f32, Cam7.xcam_rot.z));
        xf_ref = &Cam7.xf_look;
    } else {
        vec3_mul3(&Cam7.xcam_motion_tgt, Cam7.move_spd_xy, Cam7.move_spd_xy, Cam7.move_spd_z);
    }

    rv.Vec3_MulMat4x4(&Cam7.xcam_motion_tgt, &Cam7.xcam_motion_tgt, xf_ref);

    if (Cam7.move_damp) |d| {
        vec3_damp(&Cam7.xcam_motion, &Cam7.xcam_motion_tgt, d, gs.dt_f);
    } else {
        rv.Vec3_Copy(&Cam7.xcam_motion, &Cam7.xcam_motion_tgt);
    }

    rv.Vec3_AddScale1(@ptrCast(&Cam7.xf.T), @ptrCast(&Cam7.xf.T), gs.dt_f, &Cam7.xcam_motion);

    //// FIXME: remove, debug
    //rte.DrawText(0, 0, "ORBIT DIST {d:5.3}", .{Cam7.orbit_dist}, null, null) catch {};
    //if (move_sweep) {
    //    var fwd: Vec3 = .{ .y = Cam7.orbit_dist };
    //    rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
    //    rv.Vec3_Add(&Cam7.orbit_pos, @ptrCast(&Cam7.xf.T), &fwd);

    //    var mark_xf: Mat4x4 = Cam7.xf;
    //    rv.Vec3_Set(@ptrCast(&mark_xf.T), Cam7.orbit_pos.x, Cam7.orbit_pos.y, Cam7.orbit_pos.z);
    //    const mark = re.Manager.entity(.Jdge, 0).pSplineMarkers[0];
    //    if (@intFromPtr(mark) != 0) {
    //        rmo.Node_SetTransform(mark, &mark_xf);
    //        rmo.Node_SetFlags(&mark.Node, 2, 3, 16, 2);
    //        rmo.Node_SetColorsOnAllMaterials(&mark.Node, 0, 0, 255, 63, 63, 0);
    //    }
    //}

    // SOUND EFFECTS

    const vol_speed_max: f32 = @max(Cam7.move_spd_xy, 1000);
    const vol_scale: f32 = nt.pow2(@min(rv.Vec3_Mag(&Cam7.xcam_motion) / vol_speed_max, 1));
    Cam7.sfx_volume_scale = f32_damp(Cam7.sfx_volume_scale, vol_scale, 6, gs.dt_f);
    const volume = Cam7.sfx_volume * Cam7.sfx_volume_scale;
    rs.swrSound_PlaySound(28, 6, 0.35, volume, 1); // sfx_amb_wind_tat_a_loop.wav

    return .FreeCam;
}

fn UpdateState(gs: *GlobalSt, gf: *GlobalFn) void {
    CheckAndResetSavedCam(gf); // handle transition in and out of race scene
    Cam7.cam_state = switch (Cam7.cam_state) {
        .None => DoStateNone(gs, gf),
        .FreeCam => DoStateFreeCam(gs, gf),
    };
}

// math

const rot: f32 = m.pi * 2;

// TODO: move to vec lib, or find glm equivalent
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
    rc.swrCam_CamState_InitMainMat4(31, 1, @intFromPtr(&Cam7.xf), 0);
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

export fn InputUpdateA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    if (Cam7.cam_state == .FreeCam and Cam7.disable_input and rg.PAUSE_STATE.* == 0) { // kill race input
        // NOTE: unk block starting at 0xEC8820 still written to, but no observable ill-effects
        @memset(@as([*]u8, @ptrFromInt(rin.RACE_COMBINED_ADDR))[0..0x70], 0);
        @memset(@as([*]u8, @ptrFromInt(rin.RACE_BUTTON_FLOAT_HOLD_TIME_BASE_ADDR))[0..0x40], 0);
        @memset(@as([*]u8, @ptrFromInt(rin.GLOBAL_ADDR))[0..rin.GLOBAL_SIZE], 0);
    }
}

export fn OnSettingsLoad(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    HandleSettings(gf);
}

export fn EngineUpdateStage1CA(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    UpdateState(gs, gf);
}
