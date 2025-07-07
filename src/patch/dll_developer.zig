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
// - Dump font data to file on launch (font sheets and glyph templates)
// - Visualize 4x4 matrices via hijacking spline markers
// - SETTINGS:
//   dump_fonts             bool    * requires game restart to apply
//   visualize_matrices     bool

// TODO: arbitrary resource dumping?

const PLUGIN_NAME: [*:0]const u8 = "Developer";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// SWE1R-PATCHER STUFF

fn ExtractRawFontPagesToGrey8(buf: *[5][0x2000]u8) void {
    for (buf, 0..) |*b, i| {
        const page = &rf.aFontRawPageData[i];
        for (page, 0..) |px, j| {
            const px_i = j * 2;
            b[px_i + 0] = @as(u8, @intCast(ra.hExtract4BPP(px, 0))) << 4;
            b[px_i + 1] = @as(u8, @intCast(ra.hExtract4BPP(px, 1))) << 4;
        }
    }
}

fn DrawFontGlyphRegions(
    p1: ?[]u8,
    p2: ?[]u8,
    p3: ?[]u8,
    gs1: ?[]const rf.GLYPH,
    gs2: ?[]const rf.GLYPH,
    page_w: i16,
    page_h: i16,
) void {
    const pages = &[_]?[]u8{ p1, p2, p3 };
    const glyph_sets = &[_]?[]const rf.GLYPH{ gs1, gs2 };
    for (glyph_sets) |gs| {
        if (gs == null) continue;
        for (gs.?) |*g| {
            if (g._08_uv_x == -1) continue; // not implemented in font data
            assert(pages[@intCast(g._00_page_id)] != null);
            assert(pages[@intCast(g._00_page_id)].?.len == page_w * page_h);
            const page = pages[@intCast(g._00_page_id)].?;
            var px_i: usize = @intCast(g._08_uv_x + g._0A_uv_y * page_w);
            for (@intCast(g._0A_uv_y)..@intCast(g._0A_uv_y + g._0E_uv_h)) |y| {
                if (y >= page_h) continue;
                var px_j = px_i;
                for (@intCast(g._08_uv_x)..@intCast(g._08_uv_x + g._0C_uv_w)) |x| {
                    if (x >= page_w) continue;
                    page[px_j] = 0xFF;
                    px_j += 1;
                }
                px_i += @intCast(page_w);
            }
        }
    }
}

// FIXME: crashes if directory doesn't exist
// FIXME: handle FileAlreadyExists case (not sure best approach yet)
fn DumpGrey8toTGA(pixels: []const u8, width: u16, height: u16, filename: []const u8) void {
    assert(pixels.len == width * height);
    assert(width > 0);
    assert(height > 0);
    assert(filename.len > 4);
    assert(std.mem.endsWith(u8, filename, ".tga"));

    // FIXME: switch to exclusive mode and handle FileAlreadyExists
    const file = std.fs.cwd().createFile(filename, .{}) catch |e|
        PPanic("(DumpGrey8toTGA) create file: {s}", .{@errorName(e)});
    defer file.close();
    var file_bw = std.io.bufferedWriter(file.writer());
    const file_w = file_bw.writer();
    defer _ = file_bw.flush() catch |e|
        PPanic("(DumpGrey8toTGA) flush: {s}", .{@errorName(e)});

    TGA.WriteGrey8(file_w, pixels, width, height) catch |e|
        PPanic("(DumpGrey8toTGA) write tga: {s}", .{@errorName(e)});
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

    // FIXME: crashes, but only in OnInit; not on arbitrary keypress in the other
    // version, nor here on plugin hot-reload (i.e. OnInitLate)
    // TODO: make sure it only dumps once, even when hot reloading; alternatively,
    // make it dump with a button press in a menu
    fn settingsFontDump(value: Setting.Value) callconv(.C) void {
        if (value.b and !dump_fonts_done) {
            dump_fonts_done = true;
            var font: [5][0x2000]u8 = undefined;

            ExtractRawFontPagesToGrey8(&font);
            DumpGrey8toTGA(&font[0], 64, 128, "annodue/developer/fontraw0.tga");
            DumpGrey8toTGA(&font[1], 64, 128, "annodue/developer/fontraw1.tga");
            DumpGrey8toTGA(&font[2], 64, 128, "annodue/developer/fontraw2.tga");
            DumpGrey8toTGA(&font[3], 64, 128, "annodue/developer/fontraw3.tga");
            DumpGrey8toTGA(&font[4], 64, 128, "annodue/developer/fontraw4.tga");

            // TODO: resolve or filter out garbage glyph defs polluting templates
            // TODO: draw each glyph as a separate image, to account for overlaps?
            font = std.mem.zeroes([5][0x2000]u8);
            DrawFontGlyphRegions(&font[0], &font[1], &font[2], rf.aFontGlyphs0, rf.aFontGlyphs0Ext, 64, 128);
            DrawFontGlyphRegions(&font[2], null, null, rf.aFontGlyphs1, null, 64, 128);
            DrawFontGlyphRegions(&font[2], null, null, rf.aFontGlyphs2, null, 64, 128);
            DrawFontGlyphRegions(&font[3], null, null, rf.aFontGlyphs3, rf.aFontGlyphs3Ext, 64, 128);
            DrawFontGlyphRegions(&font[4], null, null, rf.aFontGlyphs4, rf.aFontGlyphs4Ext, 64, 128);
            DumpGrey8toTGA(&font[0], 64, 128, "annodue/developer/fontraw0_mask.tga");
            DumpGrey8toTGA(&font[1], 64, 128, "annodue/developer/fontraw1_mask.tga");
            DumpGrey8toTGA(&font[2], 64, 128, "annodue/developer/fontraw2_mask.tga");
            DumpGrey8toTGA(&font[3], 64, 128, "annodue/developer/fontraw3_mask.tga");
            DumpGrey8toTGA(&font[4], 64, 128, "annodue/developer/fontraw4_mask.tga");
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
