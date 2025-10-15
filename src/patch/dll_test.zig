const std = @import("std");

const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const msg = @import("util/message.zig");

const r = @import("racer");
const rt = r.Text;

const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;
const Setting = @import("core/ASettings.zig").ASettingSent;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// -
// - CONTROLS:      keyboard        xinput
//   ..             ..              ..
// - SETTINGS:
//   ..             type    note

const PLUGIN_NAME: [*:0]const u8 = "PluginTest";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

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

export fn OnInit(_: *GlobalFn) callconv(.C) void {}

export fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

// HOOKS

export fn EarlyEngineUpdateA(_: *GlobalFn) callconv(.C) void {
    //_ = gf.GDrawText(.Default, rt.MakeText(0, 0, "GDrawText Test", .{}, null, null) catch null);
}

// FIXME: remove all following after 3d api implemented; for testing

const r3d = @import("racer").@"3D";
const rm = @import("racer").Matrix;
const rv = @import("racer").Vector;
const rc = @import("racer").Camera;
const zI = std.mem.zeroInit;

// minimal 3d face proof of concept
// - main purpose is to get something on-screen via ingame api that has enough
//   steps figured out to get it looking more or less right
// - geo appears on-screen in the correct position, with the following issues
// - no clipping (at all), with side effect of offscreen vertices being drawn
// - z-projection seems to not be normalised in view space correctly; geo does
//   not visually intersect correctly?

// NOTE: not exporting to make it easier to keep code nice without affecting game
fn RenderSceneBeginA(_: *GlobalFn) callconv(.C) void {
    var vmats: rm.Mat4x3 = undefined;
    var vmat: rm.Mat4x3 = undefined;
    var rmatc = rm.Mat4x3{ // c="correction" (from collision viewer)
        .X = .{ .x = 1, .y = 0, .z = 0 },
        .Y = .{ .x = 0, .y = 0, .z = -1 },
        .Z = .{ .x = 0, .y = 1, .z = 0 },
        .T = .{ .x = 0, .y = 0, .z = 0 },
    };
    rm.Mat4x3_InvertOrthoNorm(&vmats, rc.CameraViewMatrix);
    rm.Mat4x3_Mul(&vmat, &vmats, &rmatc);
    const n = rc.gRdCameraCurrent.*.?._048_pClipFrustum.?._04_ZNear;
    const f = rc.gRdCameraCurrent.*.?._048_pClipFrustum.?._08_ZFar;
    const k = n / (f - n);

    // line drawing test

    const test_line_vtx = [_]rv.Vec3{
        rv.Vec3{ .x = 0, .y = 480, .z = 0 },
        rv.Vec3{ .x = 640, .y = 0, .z = 0 },
    };

    var lvtxt: [2]rv.Vec3 = undefined;
    var lvtxp: [2]rv.Vec3 = lvtxt;
    rm.Mat4x3_TransformPointsList(&vmat, @ptrCast(&test_line_vtx), @ptrCast(&lvtxt), 2);
    rc.gRdCameraCurrent.*.?._050_fnProjectList.?(&lvtxp, &lvtxt, 2);
    var ltlvtx = [_]r3d.D3DTLVERTEX{
        zI(r3d.D3DTLVERTEX, .{ .sx = lvtxp[0].x, .sy = lvtxp[0].y, .sz = k * lvtxp[0].z, .color = 0xFF0000FF }),
        zI(r3d.D3DTLVERTEX, .{ .sx = lvtxp[1].x, .sy = lvtxp[1].y, .sz = k * lvtxp[1].z, .color = 0xFFFFFFFF }),
    };

    r3d.fn3DSetWireframeRenderState(); // render state not implicitly called for linestrip/pointlist
    r3d.fn3DDrawLineStrip(&ltlvtx, 2);

    // face drawing test

    const test_tri_vtx = [_]rv.Vec3{
        rv.Vec3{ .x = 160, .y = 120, .z = 0 },
        rv.Vec3{ .x = 480, .y = 120, .z = 0 },
        rv.Vec3{ .x = 480, .y = 360, .z = 0 },
    };

    var vtxt: [3]rv.Vec3 = undefined;
    var vtxp: [3]rv.Vec3 = vtxt;
    rm.Mat4x3_TransformPointsList(&vmat, @ptrCast(&test_tri_vtx), @ptrCast(&vtxt), 3);
    rc.gRdCameraCurrent.*.?._050_fnProjectList.?(&vtxp, &vtxt, 3);
    var tlvtx = [_]r3d.D3DTLVERTEX{
        zI(r3d.D3DTLVERTEX, .{ .sx = vtxp[0].x, .sy = vtxp[0].y, .sz = k * vtxp[0].z, .color = 0xFFFF0000 }),
        zI(r3d.D3DTLVERTEX, .{ .sx = vtxp[1].x, .sy = vtxp[1].y, .sz = k * vtxp[1].z, .color = 0xFF00FF00 }),
        zI(r3d.D3DTLVERTEX, .{ .sx = vtxp[2].x, .sy = vtxp[2].y, .sz = k * vtxp[2].z, .color = 0xFF0000FF }),
    };

    var flags: u32 = 0x00;
    flags |= 0x0010; // default on; meaning unsure, no ref in draw fn
    flags |= 0x0002; // default on; meaning unsure, no ref in draw fn
    flags |= 0x0001; // default on; meaning unsure, no ref in draw fn
    flags |= 0x0080; // D3DTSS_MAGFILTER = 2, else 1
    //                  D3DTSS_MINFILTER = 2, else 1
    flags |= 0x0200; // D3DRS_ALPHABLENDENABLE = 1, D3DRS_TEXTUREMAPBLEND = 2
    flags |= 0x0400; // D3DRS_ALPHABLENDENABLE = 1, D3DRS_TEXTUREMAPBLEND = 4
    //                  neither = D3DRS_ALPHABLENDENABLE = 0
    flags |= 0x0800; // D3DTSS_ADDRESSU = 3, else 0
    flags |= 0x1000; // D3DTSS_ADDRESSV = 3, else 0
    //flags |= 0x2000; // D3DRS_ZWRITEENABLE = 0, else 1
    //flags |= 0x8000; // D3DRD_FOGENABLE = 1, else 0
    // render state implicitly called by this function, unlike line/point fn
    r3d.fn3DDrawTriangleList(null, flags, &tlvtx, 3, &[_]i16{ 0, 1, 2 }, 3);
}
