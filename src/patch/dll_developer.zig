const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const mem = @import("util/memory.zig");

const r = @import("racer");
const rt = r.Text;
const re = r.Entity;
const rej = r.Entity.Jdge;
const ret = r.Entity.Test;
const rm = r.Model;
const mat = r.Matrix;
const Mat4x4 = mat.Mat4x4;
const vec = r.Vector;
const Vec3 = vec.Vec3;
const rf = r.Font;
const ra = r.Asset;

const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;
const Setting = @import("core/ASettings.zig").ASettingSent;

pub const panic = @import("util/debug/debug_panic.zig").annodue_panic;

// FEATURES
// - Visualize 4x4 matrices via hijacking spline markers
// - SETTINGS:
//   visualize_matrices     bool

// TODO: arbitrary resource dumping?

const PLUGIN_NAME: [*:0]const u8 = "Developer";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// MAT4X4 VISUALIZATION

const MatVisState = struct {
    var targets: [6]?*Mat4x4 = .{ null, null, null, null, null, null };
    var params: [6][6]u8 = .{
        .{ 0xFF, 0x80, 0xFF, 0x00, 0x00, 0xFF }, // red
        .{ 0xFF, 0x80, 0x00, 0xFF, 0x00, 0xFF }, // green
        .{ 0xFF, 0x80, 0x00, 0x00, 0xFF, 0xFF }, // blue
        .{ 0xFF, 0x80, 0xFF, 0xFF, 0x00, 0xFF }, // yellow
        .{ 0xFF, 0x80, 0xFF, 0x00, 0xFF, 0xFF }, // magenta
        .{ 0xFF, 0x80, 0x00, 0xFF, 0xFF, 0xFF }, // cyan
    };
};

// SETTINGS

const Developer = struct {
    var h_s_section: ?SettingHandle = null;
    var h_s_visualize_matrices: ?SettingHandle = null;
    var s_visualize_matrices: bool = false;

    fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "developer", null);
        h_s_section = section;

        h_s_visualize_matrices =
            gf.ASettingOccupy(section, "visualize_matrices", .B, .{ .b = false }, &s_visualize_matrices, null);
    }
};

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

export fn OnInitLate(gf: *GlobalFn) callconv(.C) void {
    // NOTE: moved from OnInit due to stack overflow that only occurs if running
    // this while annodue is loading
    Developer.settingsInit(gf);
}

export fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

// HOOKS

export fn EngineUpdateStage20A(gf: *GlobalFn) callconv(.C) void {
    m44vis: {
        if (!gf.SInRace().on() or !Developer.s_visualize_matrices) break :m44vis;

        if (gf.SRaceState() == .PreRace and gf.SRaceStateNew()) {
            MatVisState.targets[0] = &ret.pPlayer.*.?.EngineXfR;
            MatVisState.targets[1] = &ret.pPlayer.*.?.EngineXfL;
            MatVisState.targets[2] = &ret.pPlayer.*.?.EngineExhaustXfR;
            MatVisState.targets[3] = &ret.pPlayer.*.?.EngineExhaustXfL;
            //MatVisState.targets[4] = &ret.pPlayer.*.?._unk_13D0;
            //MatVisState.targets[5] = &ret.pPlayer.*.?.EngineExhaustXfR;
        }

        const jdge = re.Manager.entity(.Jdge, 0);
        for (jdge.pSplineMarkers, MatVisState.targets, MatVisState.params) |m, t, p| {
            if (@intFromPtr(m) == 0 or t == null) continue;
            rm.Node_SetTransform(m, t.?);
            rm.Node_SetFlags(&m.Node, 2, 3, 16, 2);
            rm.Node_SetColorsOnAllMaterials(&m.Node, 0, 0, p[2], p[3], p[4], 0);
        }
    }
}
