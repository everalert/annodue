const Self = @This();

const std = @import("std");
const user32 = std.os.windows.user32;
const assert = std.debug.assert;

const settings = @import("settings.zig");
const s = settings.state;

const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

const MessageBoxA = user32.MessageBoxA;
const MB_OK = user32.MB_OK;
const MB_ICONINFORMATION = user32.MB_ICONINFORMATION;

// ported from swe1r-patcher

// FIXME: not crashing for now, but need to address virtualalloc size
// NOTE: probably need to investigate the actual data in memory
//   and use a real img format, without manually building the file.
//   but, what it outputs now looks right, just not sure if it's the whole data for each file
// FIXME: handle FileAlreadyExists case (not sure best approach yet)
fn DumpTexture(alloc: std.mem.Allocator, offset: usize, unk0: u8, unk1: u8, width: u32, height: u32, filename: []const u8) void {
    // Presumably the format information?
    assert(unk0 == 3);
    assert(unk1 == 0);

    // initial file setup
    const out = std.fs.cwd().createFile(filename, .{}) catch unreachable; // FIXME: switch to exclusive mode and handle FileAlreadyExists
    defer out.close();
    var out_pos: usize = 0;
    const out_head = std.fmt.allocPrintZ(alloc, "P3\n{d} {d}\n15\n", .{ width, height }) catch unreachable; // FIXME: error handling
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
        const out_frag = std.fmt.allocPrintZ(alloc, "{d} {d} {d}\n", .{ v, v, v }) catch unreachable;
        out_pos += out.pwrite(out_frag, out_pos) catch unreachable;
    }
}

// FIXME: probably want to check for annodue/textures folder and create if needed?
//   not sure if createFile in DumpTexture will handle this already
fn DumpTextureTable(alloc: std.mem.Allocator, offset: usize, unk0: u8, unk1: u8, width: u32, height: u32, filename: []const u8) u32 {
    // Get size of the table
    const count: u32 = mem.read(offset + 0, u32); // NOTE: exe unnecessary, just read ram

    // Loop over elements and dump each
    var offsets = alloc.alloc(u8, count * 4) catch unreachable;
    defer alloc.free(offsets);
    const offsets_slice = @as([*]align(1) u32, @ptrCast(offsets))[0..count];
    mem.read_bytes(offset + 4, &offsets[0], count * 4);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const filename_i = std.fmt.allocPrintZ(alloc, "annodue/textures/{s}_{d}.ppm", .{ filename, i }) catch unreachable; // FIXME: error handling
        DumpTexture(alloc, offsets_slice[i], unk0, unk1, width, height, filename_i);
    }
    return count;
}

pub fn init(alloc: std.mem.Allocator, memory: usize) usize {
    var off: usize = memory;
    if (s.mp.get("multiplayer_mod_enable", bool)) {
        if (s.mp.get("fonts_dump", bool)) {
            // This is a debug feature to dump the original font textures
            _ = DumpTextureTable(alloc, 0x4BF91C, 3, 0, 64, 128, "font0");
            _ = DumpTextureTable(alloc, 0x4BF7E4, 3, 0, 64, 128, "font1");
            _ = DumpTextureTable(alloc, 0x4BF84C, 3, 0, 64, 128, "font2");
            _ = DumpTextureTable(alloc, 0x4BF8B4, 3, 0, 64, 128, "font3");
            _ = DumpTextureTable(alloc, 0x4BF984, 3, 0, 64, 128, "font4");
        }
    }
    return off;
}
