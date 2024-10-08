const Self = @This();

const std = @import("std");

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const mem = @import("util/memory.zig");
const PPanic = @import("util/debug.zig").PPanic;

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

// FIXME: not crashing for now, but need to address virtualalloc size
// NOTE: probably need to investigate the actual data in memory
//   and use a real img format, without manually building the file.
//   but, what it outputs now looks right, just not sure if it's the whole data for each file
// FIXME: handle FileAlreadyExists case (not sure best approach yet)
fn DumpTexture(alloc: std.mem.Allocator, offset: usize, format: u8, alignment: u8, width: u32, height: u32, filename: []const u8) void {
    std.debug.assert(format == 3);
    std.debug.assert(alignment == 0);

    var buf: [255:0]u8 = undefined;

    // initial file setup
    const out = std.fs.cwd().createFile(filename, .{}) catch |e|
    // FIXME: switch to exclusive mode and handle FileAlreadyExists
        PPanic("failed to create texture dump output file: {s}", .{@errorName(e)});
    defer out.close();
    var out_pos: usize = 0;
    const out_head = std.fmt.bufPrintZ(&buf, "P3\n{d} {d}\n15\n", .{ width, height }) catch
        @panic("failed to format texture header for dump"); // FIXME: error handling
    out_pos += out.pwrite(out_head, out_pos) catch
        @panic("failed to write texture header to dump output file"); // FIXME: error handling

    // Copy the pixel data
    const texture_size = width * height; // WARNING: w*h*4/8 in original patcher, but crashes here
    var texture = alloc.alloc(u8, texture_size) catch
        @panic("failed to allocate texture dump memory");
    defer alloc.free(texture);
    const texture_slice = @as([*]u8, @ptrCast(texture))[0..texture_size];
    mem.read_bytes(offset + 4, &texture[0], texture_size);

    // write rest of file
    const len: usize = width * height * 2;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const v: u8 = ((texture_slice[i / 2] << @as(u3, @truncate((i % 2) * 4))) & 0xF0) >> 4;
        const out_frag = std.fmt.bufPrintZ(&buf, "{d} {d} {d}\n", .{ v, v, v }) catch
            @panic("failed to format texture segment for dump");
        out_pos += out.pwrite(out_frag, out_pos) catch
            @panic("failed to write texture segment to dump output file");
    }
}

// FIXME: crashes if directory doesn't exist, maybe also if file already exists
fn DumpTextureTable(offset: usize, format: u8, alignment: u8, width: u32, height: u32, filename: []const u8) u32 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var buf: [255:0]u8 = undefined;

    // Get size of the table
    const count: u32 = mem.read(offset + 0, u32); // NOTE: exe unnecessary, just read ram

    // Loop over elements and dump each
    var offsets = alloc.alloc(u8, count * 4) catch
        @panic("failed to allocate memory for texture dump table");
    defer alloc.free(offsets);
    const offsets_slice = @as([*]align(1) u32, @ptrCast(offsets))[0..count];
    mem.read_bytes(offset + 4, &offsets[0], count * 4);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const filename_i = std.fmt.bufPrintZ(&buf, "annodue/developer/{s}_{d}.ppm", .{ filename, i }) catch
            @panic("failed to format output path for texture dump table"); // FIXME: error handling
        DumpTexture(alloc, offsets_slice[i], format, alignment, width, height, filename_i);
    }
    return count;
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

    // TODO: make sure it only dumps once, even when hot reloading
    fn settingsFontDump(value: Setting.Value) callconv(.C) void {
        if (value.b and !dump_fonts_done) {
            // This is a debug feature to dump the original font textures
            // actually it's a general sprite thing, see inverse in dll_cosmetic for details
            _ = DumpTextureTable(0x4BF91C, 3, 0, 64, 128, "font0");
            _ = DumpTextureTable(0x4BF7E4, 3, 0, 64, 128, "font1");
            _ = DumpTextureTable(0x4BF84C, 3, 0, 64, 128, "font2");
            _ = DumpTextureTable(0x4BF8B4, 3, 0, 64, 128, "font3");
            _ = DumpTextureTable(0x4BF984, 3, 0, 64, 128, "font4");
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

export fn OnInit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    Developer.settingsInit(gf);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

// HOOKS

export fn EngineUpdateStage20A(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    m44vis: {
        if (!gs.in_race.on() or !Developer.s_visualize_matrices) break :m44vis;

        if (gs.race_state == .PreRace and gs.race_state_new) {
            MatVisState.targets[0] = &ret.PLAYER.*.EngineXfR;
            MatVisState.targets[1] = &ret.PLAYER.*.EngineXfL;
            MatVisState.targets[2] = &ret.PLAYER.*.EngineExhaustXfR;
            MatVisState.targets[3] = &ret.PLAYER.*.EngineExhaustXfL;
            //MatVisState.targets[4] = &ret.PLAYER.*._unk_13D0;
            //MatVisState.targets[5] = &ret.PLAYER.*.EngineExhaustXfR;
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
