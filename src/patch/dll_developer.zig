const Self = @This();

const std = @import("std");

const GlobalSt = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const debug = @import("core/Debug.zig");

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");

const mem = @import("util/memory.zig");

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// - Dump font data to file on launch
// - SETTINGS:
//   * all settings require game restart to apply
//   dump_fonts     bool

// TODO: arbitrary resource dumping?

const PLUGIN_NAME: [*:0]const u8 = "Developer";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// SWE1R-PATCHER STUFF

// FIXME: not crashing for now, but need to address virtualalloc size
// NOTE: probably need to investigate the actual data in memory
//   and use a real img format, without manually building the file.
//   but, what it outputs now looks right, just not sure if it's the whole data for each file
// FIXME: handle FileAlreadyExists case (not sure best approach yet)
fn DumpTexture(alloc: std.mem.Allocator, offset: usize, unk0: u8, unk1: u8, width: u32, height: u32, filename: []const u8) void {
    // Presumably the format information?
    std.debug.assert(unk0 == 3);
    std.debug.assert(unk1 == 0);

    var buf: [255:0]u8 = undefined;

    // initial file setup
    const out = std.fs.cwd().createFile(filename, .{}) catch unreachable; // FIXME: switch to exclusive mode and handle FileAlreadyExists
    defer out.close();
    var out_pos: usize = 0;
    const out_head = std.fmt.bufPrintZ(&buf, "P3\n{d} {d}\n15\n", .{ width, height }) catch unreachable; // FIXME: error handling
    out_pos += out.pwrite(out_head, out_pos) catch unreachable; // FIXME: error handling

    // Copy the pixel data
    const texture_size = width * height; // WARNING: w*h*4/8 in original patcher, but crashes here
    var texture = alloc.alloc(u8, texture_size) catch unreachable;
    defer alloc.free(texture);
    const texture_slice = @as([*]u8, @ptrCast(texture))[0..texture_size];
    mem.read_bytes(offset + 4, &texture[0], texture_size);

    // write rest of file
    const len: usize = width * height * 2;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const v: u8 = ((texture_slice[i / 2] << @as(u3, @truncate((i % 2) * 4))) & 0xF0) >> 4;
        const out_frag = std.fmt.bufPrintZ(&buf, "{d} {d} {d}\n", .{ v, v, v }) catch unreachable;
        out_pos += out.pwrite(out_frag, out_pos) catch unreachable;
    }
}

// FIXME: crashes if directory doesn't exist, maybe also if file already exists
fn DumpTextureTable(offset: usize, unk0: u8, unk1: u8, width: u32, height: u32, filename: []const u8) u32 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var buf: [255:0]u8 = undefined;

    // Get size of the table
    const count: u32 = mem.read(offset + 0, u32); // NOTE: exe unnecessary, just read ram

    // Loop over elements and dump each
    var offsets = alloc.alloc(u8, count * 4) catch unreachable;
    defer alloc.free(offsets);
    const offsets_slice = @as([*]align(1) u32, @ptrCast(offsets))[0..count];
    mem.read_bytes(offset + 4, &offsets[0], count * 4);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const filename_i = std.fmt.bufPrintZ(&buf, "annodue/developer/{s}_{d}.ppm", .{ filename, i }) catch unreachable; // FIXME: error handling
        DumpTexture(alloc, offsets_slice[i], unk0, unk1, width, height, filename_i);
    }
    return count;
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
    // TODO: make sure it only dumps once, even when hot reloading
    if (gf.SettingGetB("developer", "fonts_dump").?) {
        // This is a debug feature to dump the original font textures
        _ = DumpTextureTable(0x4BF91C, 3, 0, 64, 128, "font0");
        _ = DumpTextureTable(0x4BF7E4, 3, 0, 64, 128, "font1");
        _ = DumpTextureTable(0x4BF84C, 3, 0, 64, 128, "font2");
        _ = DumpTextureTable(0x4BF8B4, 3, 0, 64, 128, "font3");
        _ = DumpTextureTable(0x4BF984, 3, 0, 64, 128, "font4");
    }
}

export fn OnInitLate(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

// HOOKS

//export fn EarlyEngineUpdateAfter(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
//    _ = gv;
//    _ = initialized;
//    _ = gs;
//}
