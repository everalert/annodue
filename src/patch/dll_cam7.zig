const std = @import("std");

const m = std.math;
const rad2deg = m.radiansToDegrees;

const w32 = @import("zigwin32");
const POINT = w32.foundation.POINT;

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;

const debug = @import("core/Debug.zig");

const ButtonInputMap = @import("core/Input.zig").ButtonInputMap;
const AxisInputMap = @import("core/Input.zig").AxisInputMap;
const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;
const Setting = @import("core/ASettings.zig").ASettingSent;

const rin = @import("racer").Input;
const rc = @import("racer").Camera;
const rs = @import("racer").Sound;
const re = @import("racer").Entity;
const rg = @import("racer").Global;
const rm = @import("racer").Matrix;
const rv = @import("racer").Vector;
const Vec3 = rv.Vec3;
const Mat4x4 = rm.Mat4x4;

const sp = @import("util/spatial.zig");
const dz = @import("util/deadzone.zig");
const nt = @import("util/normalized_transform.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

// FIXME: remove, for testing
const dbg = @import("util/debug.zig");

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
//   move pod to camera         Bksp            X           hold while exiting free-cam
//   orient camera to pod       \
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

const PLUGIN_NAME: [*:0]const u8 = "Cam7";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const CamState = enum(u32) {
    None,
    FreeCam,
};

const Cam7 = extern struct {
    // ini settings
    var h_s_section: ?SettingHandle = null;
    var h_s_enable: ?SettingHandle = null;
    var h_s_flip_look_x: ?SettingHandle = null;
    var h_s_flip_look_y: ?SettingHandle = null;
    var h_s_flip_look_x_inverted: ?SettingHandle = null;
    var h_s_dz_i: ?SettingHandle = null;
    var h_s_dz_o: ?SettingHandle = null;
    var h_s_i_mouse_dpi: ?SettingHandle = null;
    var h_s_i_mouse_cm360: ?SettingHandle = null;
    var h_s_rot_damp_i_dflt: ?SettingHandle = null;
    var h_s_rot_spd_i_dflt: ?SettingHandle = null;
    var h_s_move_damp_i_dflt: ?SettingHandle = null;
    var h_s_move_spd_i_dflt: ?SettingHandle = null;
    var h_s_move_planar: ?SettingHandle = null;
    var h_s_hide_ui: ?SettingHandle = null;
    var h_s_disable_input: ?SettingHandle = null;
    var h_s_sfx_volume: ?SettingHandle = null;
    var h_s_fog_patch: ?SettingHandle = null;
    var h_s_fog_remove: ?SettingHandle = null;
    var h_s_visuals_patch: ?SettingHandle = null;
    var s_enable: bool = false;
    var s_flip_look_x: bool = false;
    var s_flip_look_y: bool = false;
    var s_flip_look_x_inverted: bool = true;
    var s_dz_i: f32 = 0.05; // 0.0..0.5
    var s_dz_o: f32 = 0.95; // 0.5..1.0
    var dz_range: f32 = 0.9; // derived
    var dz_fact: f32 = 1.0 / 0.9; // derived
    var s_i_mouse_dpi: u32 = 1600; // only needed for sens calc, does not set mouse dpi
    var s_i_mouse_cm360: f32 = 24; // real-world space per full rotation
    var i_mouse_sens: f32 = 15118.1; // derived; mouse units per full rotation
    var s_rot_damp_i_dflt: usize = 0;
    var s_rot_spd_i_dflt: usize = 3;
    var s_move_damp_i_dflt: usize = 2;
    var s_move_spd_i_dflt: usize = 3;
    var rot_damp_i: usize = 0; // derived
    var rot_spd_i: usize = 3; // derived
    var move_damp_i: usize = 2; // derived
    var move_spd_i: usize = 3; // derived
    var s_move_planar: bool = false;
    var s_hide_ui: bool = false;
    var s_disable_input: bool = false;
    var s_sfx_volume: f32 = 0.7;
    var sfx_volume_scale: f32 = 0; // derived
    var s_fog_patch: bool = true;
    var s_fog_remove: bool = false;
    var s_visuals_patch: bool = true;
    var queue_update_hide_ui: bool = false;

    const rot_damp_val = [_]?f32{ null, 36, 24, 12, 6 };
    var rot_damp: ?f32 = null;
    const rot_spd_val = [_]f32{ 80, 160, 240, 360, 540, 810 };
    const rot_change_damp: f32 = 8;
    var rot_spd: f32 = 360;
    var rot_spd_tgt: f32 = 360;
    var orbit_dist: f32 = 0;
    var orbit_dist_d: f32 = 0;
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
    var xf_plane: Mat4x4 = .{};
    var rot: Vec3 = .{};
    var rot_d: Vec3 = .{};
    var rot_d_tgt: Vec3 = .{};
    var move_d: Vec3 = .{};
    var move_d_tgt: Vec3 = .{};

    var i_toggle_data = ButtonInputMap{ .kb = .@"0", .xi = .BACK };
    var i_look_x_data = AxisInputMap{ .kb_dec = .LEFT, .kb_inc = .RIGHT, .xi_inc = .StickRX };
    var i_look_y_data = AxisInputMap{ .kb_dec = .DOWN, .kb_inc = .UP, .xi_inc = .StickRY };
    var i_move_x_data = AxisInputMap{ .kb_dec = .A, .kb_inc = .D, .xi_inc = .StickLX };
    var i_move_y_data = AxisInputMap{ .kb_dec = .S, .kb_inc = .W, .xi_inc = .StickLY };
    var i_move_z_data = AxisInputMap{ .kb_dec = .SHIFT, .kb_inc = .SPACE, .xi_dec = .TriggerR, .xi_inc = .TriggerL };
    var i_movement_dec_data = ButtonInputMap{ .kb = .Q, .xi = .LEFT_SHOULDER };
    var i_movement_inc_data = ButtonInputMap{ .kb = .E, .xi = .RIGHT_SHOULDER };
    var i_rotation_dec_data = ButtonInputMap{ .kb = .Z, .xi = .LEFT_THUMB };
    var i_rotation_inc_data = ButtonInputMap{ .kb = .C, .xi = .RIGHT_THUMB };
    var i_damp_data = ButtonInputMap{ .kb = .X, .xi = .Y };
    var i_planar_data = ButtonInputMap{ .kb = .TAB, .xi = .B };
    var i_sweep_data = ButtonInputMap{ .kb = .RCONTROL, .xi = .X };
    //var i_mpan_data = ButtonInputMap{ .kb = .LBUTTON };
    //var i_morbit_data = ButtonInputMap{ .kb = .RBUTTON };
    var i_hide_ui_data = ButtonInputMap{ .kb = .@"6" };
    var i_disable_input_data = ButtonInputMap{ .kb = .@"7" };
    var i_move_vehicle_data = ButtonInputMap{ .kb = .BACK, .xi = .X };
    var i_look_at_vehicle_data = ButtonInputMap{ .kb = .OEM_5 }; // backslash
    var i_toggle = i_toggle_data.inputMap();
    var i_look_x = i_look_x_data.inputMap();
    var i_look_y = i_look_y_data.inputMap();
    var i_move_x = i_move_x_data.inputMap();
    var i_move_y = i_move_y_data.inputMap();
    var i_move_z = i_move_z_data.inputMap();
    var i_movement_dec = i_movement_dec_data.inputMap();
    var i_movement_inc = i_movement_inc_data.inputMap();
    var i_rotation_dec = i_rotation_dec_data.inputMap();
    var i_rotation_inc = i_rotation_inc_data.inputMap();
    var i_damp = i_damp_data.inputMap();
    var i_planar = i_planar_data.inputMap();
    var i_sweep = i_sweep_data.inputMap();
    var i_hide_ui = i_hide_ui_data.inputMap();
    var i_disable_input = i_disable_input_data.inputMap();
    var i_move_vehicle = i_move_vehicle_data.inputMap();
    var i_look_at_vehicle = i_look_at_vehicle_data.inputMap();
    var i_mouse_d_x: f32 = 0;
    var i_mouse_d_y: f32 = 0;

    // TODO: maybe normalizing XY stuff (or do it at input system level)
    fn update_input(gf: *GlobalFn) void {
        i_toggle.update(gf);
        i_look_x.update(gf);
        i_look_y.update(gf);
        i_move_x.update(gf);
        i_move_y.update(gf);
        i_move_z.update(gf);
        i_movement_dec.update(gf);
        i_movement_inc.update(gf);
        i_rotation_dec.update(gf);
        i_rotation_inc.update(gf);
        i_damp.update(gf);
        i_planar.update(gf);
        i_sweep.update(gf);
        i_hide_ui.update(gf);
        i_disable_input.update(gf);
        i_move_vehicle.update(gf);
        i_look_at_vehicle.update(gf);

        if (cam_state == .FreeCam and rg.PAUSE_STATE.* == 0) {
            gf.InputLockMouse();
            // TODO: move to InputMap (after input customization)
            const mouse_d: POINT = gf.InputGetMouseDelta();
            i_mouse_d_x = @as(f32, @floatFromInt(mouse_d.x)) / i_mouse_sens;
            i_mouse_d_y = @as(f32, @floatFromInt(mouse_d.y)) / i_mouse_sens;
        }
    }

    fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "cam7", settingsUpdate);
        h_s_section = section;

        h_s_enable =
            gf.ASettingOccupy(section, "enable", .B, .{ .b = false }, &s_enable, null);

        h_s_fog_patch =
            gf.ASettingOccupy(section, "fog_patch", .B, .{ .b = true }, &s_fog_patch, null);
        h_s_fog_remove =
            gf.ASettingOccupy(section, "fog_remove", .B, .{ .b = false }, &s_fog_remove, null);
        h_s_visuals_patch =
            gf.ASettingOccupy(section, "visuals_patch", .B, .{ .b = true }, &s_visuals_patch, null);

        h_s_flip_look_x =
            gf.ASettingOccupy(section, "flip_look_x", .B, .{ .b = false }, &s_flip_look_x, null);
        h_s_flip_look_y =
            gf.ASettingOccupy(section, "flip_look_y", .B, .{ .b = false }, &s_flip_look_y, null);
        h_s_flip_look_x_inverted =
            gf.ASettingOccupy(section, "flip_look_x_inverted", .B, .{ .b = false }, &s_flip_look_x_inverted, null);

        h_s_dz_i =
            gf.ASettingOccupy(section, "stick_deadzone_inner", .F, .{ .f = 0.05 }, &s_dz_i, null);
        h_s_dz_o =
            gf.ASettingOccupy(section, "stick_deadzone_outer", .F, .{ .f = 0.95 }, &s_dz_o, null);

        h_s_i_mouse_dpi =
            gf.ASettingOccupy(section, "mouse_dpi", .U, .{ .u = 1600 }, &s_i_mouse_dpi, null);
        h_s_i_mouse_cm360 =
            gf.ASettingOccupy(section, "mouse_cm360", .F, .{ .f = 24 }, &s_i_mouse_cm360, null);

        h_s_rot_damp_i_dflt =
            gf.ASettingOccupy(section, "default_rotation_smoothing", .U, .{ .u = 0 }, &s_rot_damp_i_dflt, null);
        h_s_rot_spd_i_dflt =
            gf.ASettingOccupy(section, "default_rotation_speed", .U, .{ .u = 3 }, &s_rot_spd_i_dflt, null);
        h_s_move_damp_i_dflt =
            gf.ASettingOccupy(section, "default_move_smoothing", .U, .{ .u = 2 }, &s_move_damp_i_dflt, null);
        h_s_move_spd_i_dflt =
            gf.ASettingOccupy(section, "default_move_speed", .U, .{ .u = 3 }, &s_move_spd_i_dflt, null);
        h_s_move_planar =
            gf.ASettingOccupy(section, "default_planar_movement", .B, .{ .b = false }, &s_move_planar, null);

        h_s_hide_ui =
            gf.ASettingOccupy(section, "default_hide_ui", .B, .{ .b = false }, &s_hide_ui, null);
        h_s_disable_input =
            gf.ASettingOccupy(section, "default_disable_input", .B, .{ .b = false }, &s_disable_input, null);
        h_s_sfx_volume =
            gf.ASettingOccupy(section, "sfx_volume", .F, .{ .f = 0.7 }, &s_sfx_volume, null);
    }

    // TODO: rethink default -> live setting flow during settings reload, for the relevant settings
    fn settingsUpdate(changed: [*]Setting, len: usize) callconv(.C) void {
        var update_mouse_sens: bool = false;
        var update_deadzone: bool = false;

        for (changed, 0..len) |setting, _| {
            const nlen: usize = std.mem.len(setting.name);

            if ((nlen == 9 and std.mem.eql(u8, "fog_patch", setting.name[0..nlen]) or
                nlen == 10 and std.mem.eql(u8, "fog_remove", setting.name[0..nlen])) and
                cam_state == .FreeCam)
            {
                patchFog(s_fog_patch);
                continue;
            }
            if (nlen == 13 and std.mem.eql(u8, "visuals_patch", setting.name[0..nlen]) and
                cam_state == .FreeCam)
            {
                patchFlags(s_visuals_patch);
                continue;
            }

            if (nlen == 9 and std.mem.eql(u8, "mouse_dpi", setting.name[0..nlen]) or
                nlen == 11 and std.mem.eql(u8, "mouse_cm360", setting.name[0..nlen]))
            {
                update_mouse_sens = true;
                continue;
            }

            if (nlen == 20 and std.mem.eql(u8, "stick_deadzone_inner", setting.name[0..nlen])) {
                s_dz_i = m.clamp(s_dz_i, 0.000, 0.495);
                update_deadzone = true;
                continue;
            }
            if (nlen == 20 and std.mem.eql(u8, "stick_deadzone_outer", setting.name[0..nlen])) {
                s_dz_o = m.clamp(s_dz_o, 0.505, 1.000);
                update_deadzone = true;
                continue;
            }

            // TODO: keep settings file in sync with these, to remember between sessions (after settings rework)
            if (nlen == 26 and std.mem.eql(u8, "default_rotation_smoothing", setting.name[0..nlen])) {
                s_rot_damp_i_dflt = m.clamp(s_rot_damp_i_dflt, 0, 4);
                rot_damp_i = s_rot_damp_i_dflt;
                rot_damp = rot_damp_val[rot_damp_i];
                continue;
            }
            if (nlen == 22 and std.mem.eql(u8, "default_rotation_speed", setting.name[0..nlen])) {
                s_rot_spd_i_dflt = m.clamp(s_rot_spd_i_dflt, 0, 5);
                rot_spd_i = s_rot_spd_i_dflt;
                rot_spd_tgt = rot_spd_val[rot_spd_i];
                continue;
            }
            if (nlen == 22 and std.mem.eql(u8, "default_move_smoothing", setting.name[0..nlen])) {
                s_move_damp_i_dflt = m.clamp(s_move_damp_i_dflt, 0, 3);
                move_damp_i = s_move_damp_i_dflt;
                move_damp = move_damp_val[move_damp_i];
                continue;
            }
            if (nlen == 18 and std.mem.eql(u8, "default_move_speed", setting.name[0..nlen])) {
                s_move_spd_i_dflt = m.clamp(s_move_spd_i_dflt, 0, 6);
                move_spd_i = s_move_spd_i_dflt;
                move_spd_xy_tgt = move_spd_xy_val[move_spd_i];
                move_spd_z_tgt = move_spd_z_val[move_spd_i];
                continue;
            }

            if (nlen == 15 and std.mem.eql(u8, "default_hide_ui", setting.name[0..nlen]) and
                cam_state == .FreeCam)
            {
                queue_update_hide_ui = true;
                continue;
            }
        }

        if (update_mouse_sens)
            i_mouse_sens = s_i_mouse_cm360 / 2.54 * @as(f32, @floatFromInt(s_i_mouse_dpi));

        if (update_deadzone) {
            dz_range = s_dz_o - s_dz_i;
            dz_fact = 1 / dz_range;
        }
    }
};

const camstate_ref_addr: u32 = rc.METACAM_ARRAY_ADDR + 0x170; // = metacam index 1 0x04

fn patchFlags(on: bool) void {
    if (on) {
        _ = x86.mov_eax_imm32(0x453FA1, u32, 1); // map visual flags-related check
    } else {
        _ = x86.mov_eax_moffs32(0x453FA1, 0x50CA3C); // map visual flags-related check
    }
}

fn patchFog(on: bool) void {
    if (on) {
        const dist = if (Cam7.s_fog_remove) comptime m.pow(f32, 10, 10) else Cam7.fog_dist;
        var o = x86.mov_ecx_imm32(0x4539A0, u32, @as(u32, @bitCast(dist))); // fog dist, normal case
        _ = x86.nop_until(o, 0x4539A6);
        _ = x86.mov_espoff_imm32(0x4539AC, 0x24, @bitCast(dist)); // fog dist, flags @0=1 case
        return;
    }
    _ = x86.mov_ecx_u32(0x4539A0, 0x2D8); // fog dist, normal case
    _ = x86.mov_espoff_imm32(0x4539AC, 0x24, 0xBF800000); // fog dist, flags @0=1 case (-1.0)
}

fn patchFOV(on: bool) void {
    const fov: f32 = if (on) 100 else 120; // first-person internal cam fov
    _ = mem.write(0x4528EF, f32, fov); // instruction at 0x4528E9
}

inline fn CamTransitionOut() void {
    patchFlags(false);
    patchFog(false);
    patchFOV(false);
    Cam7.move_d_tgt = .{};
    Cam7.move_d = .{};
    Cam7.saved_camstate_index = null;
}

fn SaveSavedCam() void {
    if (Cam7.saved_camstate_index != null) return;
    Cam7.saved_camstate_index = mem.read(camstate_ref_addr, u32);

    const mat4_addr: u32 = rc.CAMSTATE_ARRAY_ADDR +
        Cam7.saved_camstate_index.? * rc.CAMSTATE_ITEM_SIZE + 0x14;
    @memcpy(@as(*[16]f32, @ptrCast(&Cam7.xf)), @as([*]f32, @ptrFromInt(mat4_addr)));
    sp.mat4x4_getEuler(&Cam7.xf, &Cam7.rot);

    patchFlags(Cam7.s_visuals_patch);
    patchFog(Cam7.s_fog_patch);
    patchFOV(true);

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
    _ = gf.GHideRaceUIOff();
}

fn UpdateHideUI(gf: *GlobalFn) void {
    if (Cam7.s_hide_ui and Cam7.cam_state == .FreeCam) {
        _ = gf.GHideRaceUIOn();
        return;
    }

    _ = gf.GHideRaceUIOff();
}

// STATE MACHINE

fn DoStateNone(_: *GlobalSt, gf: *GlobalFn) CamState {
    if (Cam7.i_toggle.gets() == .JustOn and Cam7.s_enable) {
        SaveSavedCam();
        if (Cam7.s_hide_ui) _ = gf.GHideRaceUIOn();
        return .FreeCam;
    }
    return .None;
}

fn DoStateFreeCam(gs: *GlobalSt, gf: *GlobalFn) CamState {
    if (Cam7.i_toggle.gets() == .JustOn or !Cam7.s_enable) {
        if (gs.race_state != .None and Cam7.i_move_vehicle.gets().on()) {
            re.Test.DoRespawn(re.Test.PLAYER.*, 0);
            re.Test.PLAYER.*._collision_toggles = 0xFFFFFFFF;
            re.Test.PLAYER.*.transform = Cam7.xf;
            var fwd: Vec3 = .{ .y = 11 };
            rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
            rv.Vec3_Add(@ptrCast(&re.Test.PLAYER.*.transform.T), @ptrCast(&re.Test.PLAYER.*.transform.T), &fwd);

            for (re.Manager.entitySliceAllObj(.cMan)) |*cman| {
                if (cman.pTest != null) {
                    const anim_mode = cman.mode;
                    cman.animTimer = 8;
                    re.cMan.DoPreRaceSweep(cman);
                    cman.mode = anim_mode;
                    cman.visualFlags = 0xFFFFFF00;
                }
            }
        }

        RestoreSavedCam();
        _ = gf.GHideRaceUIOff();
        return .None;
    }

    if (Cam7.queue_update_hide_ui) {
        Cam7.queue_update_hide_ui = false;
        UpdateHideUI(gf);
    }

    // input

    if (Cam7.i_planar.gets() == .JustOn)
        Cam7.s_move_planar = !Cam7.s_move_planar;

    if (Cam7.i_hide_ui.gets() == .JustOn) {
        Cam7.s_hide_ui = !Cam7.s_hide_ui;
        if (Cam7.h_s_hide_ui) |h| gf.ASettingUpdate(h, .{ .b = Cam7.s_hide_ui });
        UpdateHideUI(gf);
    }

    if (Cam7.i_disable_input.gets() == .JustOn) {
        Cam7.s_disable_input = !Cam7.s_disable_input;
        if (Cam7.h_s_disable_input) |h| gf.ASettingUpdate(h, .{ .b = Cam7.s_disable_input });
    }

    const move_sweep: bool = Cam7.i_sweep.gets().on();
    if (Cam7.i_sweep.gets() == .JustOn) {
        Cam7.orbit_dist = 200;
        Cam7.orbit_dist_d = 0;
        var fwd: Vec3 = .{ .y = Cam7.orbit_dist };
        rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
        rv.Vec3_Add(&Cam7.orbit_pos, @ptrCast(&Cam7.xf.T), &fwd);
    }

    const move_dec: bool = Cam7.i_movement_dec.gets() == .JustOn;
    const move_inc: bool = Cam7.i_movement_inc.gets() == .JustOn;
    const move_both: bool = (move_dec and Cam7.i_movement_inc.gets().on()) or
        (move_inc and Cam7.i_movement_dec.gets().on());
    if (Cam7.i_damp.gets().on()) {
        if (move_dec and Cam7.move_damp_i > 0) Cam7.move_damp_i -= 1;
        if (move_inc and Cam7.move_damp_i < 3) Cam7.move_damp_i += 1;
        if (move_both) Cam7.move_damp_i = Cam7.s_move_damp_i_dflt;
        Cam7.move_damp = Cam7.move_damp_val[Cam7.move_damp_i];
    } else {
        if (move_dec and Cam7.move_spd_i > 0) Cam7.move_spd_i -= 1;
        if (move_inc and Cam7.move_spd_i < 7) Cam7.move_spd_i += 1;
        if (move_both) Cam7.move_spd_i = Cam7.s_move_spd_i_dflt;
        Cam7.move_spd_xy_tgt = Cam7.move_spd_xy_val[Cam7.move_spd_i];
        Cam7.move_spd_z_tgt = Cam7.move_spd_z_val[Cam7.move_spd_i];
    }
    Cam7.move_spd_xy = sp.f32_damp(Cam7.move_spd_xy, Cam7.move_spd_xy_tgt, Cam7.move_change_damp, gs.dt_f);
    Cam7.move_spd_z = sp.f32_damp(Cam7.move_spd_z, Cam7.move_spd_z_tgt, Cam7.move_change_damp, gs.dt_f);

    const rot_dec: bool = Cam7.i_rotation_dec.gets() == .JustOn;
    const rot_inc: bool = Cam7.i_rotation_inc.gets() == .JustOn;
    const rot_both: bool = (rot_dec and Cam7.i_rotation_inc.gets().on()) or
        (rot_inc and Cam7.i_rotation_dec.gets().on());
    if (Cam7.i_damp.gets().on()) {
        if (rot_dec and Cam7.rot_damp_i > 0) Cam7.rot_damp_i -= 1;
        if (rot_inc and Cam7.rot_damp_i < 4) Cam7.rot_damp_i += 1;
        if (rot_both) Cam7.rot_damp_i = Cam7.s_rot_damp_i_dflt;
        Cam7.rot_damp = Cam7.rot_damp_val[Cam7.rot_damp_i];
    } else {
        if (rot_dec and Cam7.rot_spd_i > 0) Cam7.rot_spd_i -= 1;
        if (rot_inc and Cam7.rot_spd_i < 5) Cam7.rot_spd_i += 1;
        if (rot_both) Cam7.rot_spd_i = Cam7.s_rot_spd_i_dflt;
        Cam7.rot_spd_tgt = Cam7.rot_spd_val[Cam7.rot_spd_i];
    }
    Cam7.rot_spd = sp.f32_damp(Cam7.rot_spd, Cam7.rot_spd_tgt, Cam7.rot_change_damp, gs.dt_f);

    const upside_down: bool = @mod(Cam7.rot.y / (m.pi * 2) - 0.25, 1) < 0.5;

    // rotation

    const using_mouse: bool = Cam7.i_mouse_d_x != 0 or Cam7.i_mouse_d_y != 0;
    const flip_x: bool = Cam7.s_flip_look_x != (Cam7.s_flip_look_x_inverted and upside_down);

    var rot_scale: f32 = m.pi * 2;
    Cam7.rot_d.x = if (using_mouse) -Cam7.i_mouse_d_x else -Cam7.i_look_x.getf();
    Cam7.rot_d.y = if (using_mouse) -Cam7.i_mouse_d_y else Cam7.i_look_y.getf();
    if (flip_x) Cam7.rot_d.x = -Cam7.rot_d.x;
    if (Cam7.s_flip_look_y) Cam7.rot_d.y = -Cam7.rot_d.y;
    if (!using_mouse) {
        dz.vec2_applyDeadzoneSq(@ptrCast(&Cam7.rot_d), Cam7.s_dz_i, Cam7.dz_range, Cam7.dz_fact);
        const r_scale: f32 = nt.smooth2(rv.Vec2_Mag(@ptrCast(&Cam7.rot_d)));
        rv.Vec2_Scale(@ptrCast(&Cam7.rot_d), r_scale, @ptrCast(&Cam7.rot_d));
        rot_scale = gs.dt_f * Cam7.rot_spd / 360 * m.pi * 2;
    }

    if (!using_mouse and Cam7.rot_damp != null) {
        sp.vec3_damp(&Cam7.rot_d_tgt, &Cam7.rot_d, Cam7.rot_damp.?, gs.dt_f);
        rv.Vec3_AddScale1(&Cam7.rot, &Cam7.rot, rot_scale, &Cam7.rot_d_tgt);
    } else {
        rv.Vec3_Copy(&Cam7.rot_d_tgt, &Cam7.rot_d);
        rv.Vec3_AddScale1(&Cam7.rot, &Cam7.rot, rot_scale, &Cam7.rot_d);
    }
    Cam7.rot.z = sp.f32_damp(Cam7.rot.z, 0, 8, gs.dt_f); // NOTE: straighten out, not for drone

    if (move_sweep) {
        var fwd: Vec3 = .{ .y = Cam7.orbit_dist };
        rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
        rv.Vec3_Add(&Cam7.orbit_pos, @ptrCast(&Cam7.xf.T), &fwd);
    }

    sp.mat4x4_setRotation(&Cam7.xf, &Cam7.rot);

    if (move_sweep) {
        var fwd: Vec3 = .{ .y = Cam7.orbit_dist };
        rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
        rv.Vec3_Sub(@ptrCast(&Cam7.xf.T), &Cam7.orbit_pos, &fwd);
    }

    // motion

    var xf_fwd_ref: *Mat4x4 = &Cam7.xf;

    Cam7.move_d_tgt.z = Cam7.i_move_z.getf();
    dz.f32_applyDeadzoneSq(&Cam7.move_d_tgt.z, Cam7.s_dz_i, Cam7.dz_range, Cam7.dz_fact);
    Cam7.move_d_tgt.z = nt.smooth4(Cam7.move_d_tgt.z);

    Cam7.move_d_tgt.x = Cam7.i_move_x.getf();
    Cam7.move_d_tgt.y = Cam7.i_move_y.getf();
    dz.vec2_applyDeadzoneSq(@ptrCast(&Cam7.move_d_tgt), Cam7.s_dz_i, Cam7.dz_range, Cam7.dz_fact);

    // TODO: state machine enum, probably
    if (move_sweep) {
        var orbit_dist_d_tgt: f32 = Cam7.move_d_tgt.z;
        Cam7.move_d_tgt.z = Cam7.move_d_tgt.y;
        sp.vec3_mul3(&Cam7.move_d_tgt, Cam7.move_spd_xy, 0, Cam7.move_spd_xy);

        Cam7.orbit_dist_d = if (Cam7.move_damp) |d| sp.f32_damp(Cam7.orbit_dist_d, orbit_dist_d_tgt, d, gs.dt_f) else orbit_dist_d_tgt;
        var dist_d: f32 = Cam7.orbit_dist_d * Cam7.move_spd_z * gs.dt_f;
        if (Cam7.orbit_dist + dist_d < 0) dist_d = -Cam7.orbit_dist;
        var fwd: Vec3 = .{ .y = dist_d };
        Cam7.orbit_dist += dist_d;
        rv.Vec3_MulMat4x4(&fwd, &fwd, &Cam7.xf);
        rv.Vec3_Sub(@ptrCast(&Cam7.xf.T), @ptrCast(&Cam7.xf.T), &fwd);
    } else if (Cam7.s_move_planar) {
        if (upside_down) {
            Cam7.move_d_tgt.y = -Cam7.move_d_tgt.y;
            Cam7.move_d_tgt.z = -Cam7.move_d_tgt.z;
        }
        sp.vec3_mul3(&Cam7.move_d_tgt, Cam7.move_spd_xy, Cam7.move_spd_xy, Cam7.move_spd_z);

        rm.Mat4x4_SetRotation(&Cam7.xf_plane, rad2deg(f32, Cam7.rot.x), 0, rad2deg(f32, Cam7.rot.z));
        xf_fwd_ref = &Cam7.xf_plane;
    } else {
        sp.vec3_mul3(&Cam7.move_d_tgt, Cam7.move_spd_xy, Cam7.move_spd_xy, Cam7.move_spd_z);
    }

    rv.Vec3_MulMat4x4(&Cam7.move_d_tgt, &Cam7.move_d_tgt, xf_fwd_ref);

    if (Cam7.move_damp) |d| {
        sp.vec3_damp(&Cam7.move_d, &Cam7.move_d_tgt, d, gs.dt_f);
    } else {
        rv.Vec3_Copy(&Cam7.move_d, &Cam7.move_d_tgt);
    }

    rv.Vec3_AddScale1(@ptrCast(&Cam7.xf.T), @ptrCast(&Cam7.xf.T), gs.dt_f, &Cam7.move_d);

    // LOOK TO HOME

    if (Cam7.i_look_at_vehicle.gets().on()) blk: {
        var dir: Vec3 = undefined;
        rv.Vec3_Sub(&dir, @ptrCast(&re.Test.PLAYER.*.transform.T), @ptrCast(&Cam7.xf.T));
        if (!sp.vec3_norm(&dir)) break :blk;

        var dirEulerXY: Vec3 = undefined;
        sp.vec3_dirToEulerXY(&dirEulerXY, &dir);
        sp.mat4x4_setRotation(&Cam7.xf, &dirEulerXY);
        Cam7.rot = dirEulerXY;
    }

    // SOUND EFFECTS

    const vol_speed_max: f32 = @max(Cam7.move_spd_xy, 1000);
    const vol_scale: f32 = nt.pow2(@min(rv.Vec3_Mag(&Cam7.move_d) / vol_speed_max, 1));
    Cam7.sfx_volume_scale = sp.f32_damp(Cam7.sfx_volume_scale, vol_scale, 6, gs.dt_f);
    const volume = Cam7.s_sfx_volume * Cam7.sfx_volume_scale;
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
    Cam7.settingsInit(gf);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    rc.swrCam_CamState_InitMainMat4(31, 1, @intFromPtr(&Cam7.xf), 0);
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
    if (Cam7.cam_state == .FreeCam and Cam7.s_disable_input and rg.PAUSE_STATE.* == 0) { // kill race input
        // NOTE: unk block starting at 0xEC8820 still written to, but no observable ill-effects
        @memset(@as([*]u8, @ptrFromInt(rin.RACE_COMBINED_ADDR))[0..0x70], 0);
        @memset(@as([*]u8, @ptrFromInt(rin.RACE_BUTTON_FLOAT_HOLD_TIME_BASE_ADDR))[0..0x40], 0);
        @memset(@as([*]u8, @ptrFromInt(rin.GLOBAL_ADDR))[0..rin.GLOBAL_SIZE], 0);
    }
}

//export fn OnSettingsLoad(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
//    HandleSettings(gf);
//}

export fn EngineUpdateStage1CA(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    UpdateState(gs, gf);
}
