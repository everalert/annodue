const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const mem = @import("util/memory.zig");
const PPanic = @import("util/debug.zig").PPanic;
const TGA = @import("util/tga.zig");

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

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// - Dump font data to file on launch
// - Visualize 4x4 matrices via hijacking spline markers
// - SETTINGS:
//   dump_fonts             bool    * requires game restart to apply
//   visualize_matrices     bool

// TODO: arbitrary resource dumping?

const PLUGIN_NAME: [*:0]const u8 = "Developer";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// SWE1R-PATCHER STUFF

// FIXME: crashes if directory doesn't exist
// FIXME: handle FileAlreadyExists case (not sure best approach yet)
fn DumpGrey4toTGA(pixels: []const u8, width: u16, height: u16, filename: []const u8) void {
    assert(pixels.len == width * height / 2);
    assert(width > 0);
    assert(height > 0);
    assert(filename.len > 4);
    assert(std.mem.endsWith(u8, filename, ".tga"));

    // setup file
    // FIXME: switch to exclusive mode and handle FileAlreadyExists
    const file = std.fs.cwd().createFile(filename, .{}) catch |e|
        PPanic("(DumpGrey4toTGA) create file: {s}", .{@errorName(e)});
    defer file.close();
    var file_bw = std.io.bufferedWriter(file.writer());
    const file_w = file_bw.writer();
    defer _ = file_bw.flush() catch |e|
        PPanic("(DumpGrey4toTGA) flush: {s}", .{@errorName(e)});

    // write tga
    var tga = TGA{
        .ImageType = .{ .DataType = .Grayscale },
        .ImageWidth = width,
        .ImageHeight = height,
        .ImageBPP = 8,
    };
    tga.WriteHeader(file_w) catch |e|
        PPanic("(DumpGrey4toTGA) tga header: {s}", .{@errorName(e)});
    for (pixels, 0..) |px, i| {
        const px_i = i * 2;
        file_w.writeIntLittle(u8, @as(u8, @intCast(ra.hExtract4BPP(px, 0))) << 4) catch |e|
            PPanic("(DumpGrey4toTGA) pixel {d}: {s}", .{ px_i + 0, @errorName(e) });
        file_w.writeIntLittle(u8, @as(u8, @intCast(ra.hExtract4BPP(px, 1))) << 4) catch |e|
            PPanic("(DumpGrey4toTGA) pixel {d}: {s}", .{ px_i + 1, @errorName(e) });
    }
    tga.WriteFooter(file_w) catch |e|
        PPanic("(DumpGrey4toTGA) tga footer: {s}", .{@errorName(e)});
}

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
    var h_s_dump_fonts: ?SettingHandle = null;
    var h_s_visualize_matrices: ?SettingHandle = null;
    var s_dump_fonts: bool = false;
    var dump_fonts_done: bool = false;
    var s_visualize_matrices: bool = false;

    fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "developer", null);
        h_s_section = section;

        h_s_dump_fonts = // working?
            gf.ASettingOccupy(section, "dump_fonts", .B, .{ .b = false }, &s_dump_fonts, settingsFontDump);
        h_s_visualize_matrices =
            gf.ASettingOccupy(section, "visualize_matrices", .B, .{ .b = false }, &s_visualize_matrices, null);
    }

    // TODO: dump font mask sheet to tga;  i.e. images showing UV regions of each glyph
    // TODO: make sure it only dumps once, even when hot reloading; alternatively,
    // make it dump with a button press in a menu
    fn settingsFontDump(value: Setting.Value) callconv(.C) void {
        if (value.b and !dump_fonts_done) {
            DumpGrey4toTGA(&rf.aFontRawPageData[0], 64, 128, "annodue/developer/fontraw0.tga");
            DumpGrey4toTGA(&rf.aFontRawPageData[1], 64, 128, "annodue/developer/fontraw1.tga");
            DumpGrey4toTGA(&rf.aFontRawPageData[2], 64, 128, "annodue/developer/fontraw2.tga");
            DumpGrey4toTGA(&rf.aFontRawPageData[3], 64, 128, "annodue/developer/fontraw3.tga");
            DumpGrey4toTGA(&rf.aFontRawPageData[4], 64, 128, "annodue/developer/fontraw4.tga");
            dump_fonts_done = true;
        }
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

export fn OnInit(gf: *GlobalFn) callconv(.C) void {
    Developer.settingsInit(gf);
}

export fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

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
