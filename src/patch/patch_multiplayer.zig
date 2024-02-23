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

// NOTE: max data size 256
// FIXME: new guid not equivalent to swe1r-patcher for some reason, but close
fn ModifyNetworkGuid(data: []u8) void {
    // RC4 hash
    const state = struct {
        var s: [256]u8 = undefined;
        var initialized: bool = false;
    };
    if (!state.initialized) {
        var i: usize = 0;
        while (i < 256) : (i += 1) {
            state.s[i] = @truncate(i);
        }
        state.initialized = true;
    }

    assert(data.len <= 256);
    var i: usize = 0;
    var j: u8 = 0;
    while (i < 256) : (i += 1) {
        j +%= state.s[i] +% data[i % data.len];
        std.mem.swap(u8, &state.s[i], &state.s[j]);
    }

    var k_i: u8 = 0;
    var k_j: u8 = 0;
    var k_s: [256]u8 = undefined;
    @memcpy(&k_s, &state.s);
    i = 0;
    while (i < 16) : (i += 1) {
        k_i += 1;
        k_j +%= k_s[k_i];
        std.mem.swap(u8, &k_s[k_i], &k_s[k_j]);
        var idx: usize = (@as(usize, k_s[k_i]) + k_s[k_j]) % 0xFF;
        var rc4_output: u8 = k_s[idx];
        _ = mem.write(0x4AF9B0 + i, u8, rc4_output);
    }

    // Overwrite the first 2 byte with a version index, so we have room
    // to fix the algorithm if we have messed up
    _ = mem.write(0x4AF9B0 + 0, u16, 0x00000000);
}

fn PatchNetworkUpgrades(memory_offset: usize, upgrade_levels: *[7]u8, upgrade_healths: *[7]u8, patch_guid: bool) usize {
    if (patch_guid) {
        ModifyNetworkGuid(@constCast("Upgrades"));
        ModifyNetworkGuid(upgrade_levels);
        ModifyNetworkGuid(upgrade_healths);
    }

    var offset: usize = memory_offset;

    // Update menu upgrades
    _ = mem.write(0x45CFC6, u8, 0x05); // levels
    _ = mem.write(0x45CFCB, u8, 0xFF); // healths

    // Place upgrade data in memory
    const off_up_lv: usize = offset;
    offset = mem.write(offset, @TypeOf(upgrade_levels.*), upgrade_levels.*);
    const off_up_hp: usize = offset;
    offset = mem.write(offset, @TypeOf(upgrade_healths.*), upgrade_healths.*);

    // Construct our code
    const off_upgrade_code: usize = offset;
    offset = x86.push_edx(offset);
    offset = x86.push_eax(offset);
    offset = x86.push_u32(offset, off_up_hp);
    offset = x86.push_u32(offset, off_up_lv);
    offset = x86.push_esi(offset);
    offset = x86.push_edi(offset);
    offset = x86.call(offset, 0x449D00); // ???
    offset = x86.add_esp8(offset, 0x10);
    offset = x86.pop_eax(offset);
    offset = x86.pop_edx(offset);
    offset = x86.retn(offset);

    // Install it by jumping from 0x45B765 and returning to 0x45B76C
    var off_install: usize = 0x45B765;
    off_install = x86.call(off_install, off_upgrade_code);
    off_install = x86.nop(off_install);
    off_install = x86.nop(off_install);

    return offset;
}

// WARNING: not tested
fn PatchNetworkCollisions(memory_offset: usize, patch_guid: bool) usize {
    // Disable collision between network players
    if (patch_guid) {
        ModifyNetworkGuid(@constCast("Collisions"));
    }

    var offset: usize = memory_offset;
    const memory_offset_collision_code: usize = memory_offset;

    // Inject new code
    offset = x86.push_edx(offset);
    offset = x86.mov_edx(offset, 0x4D5E00); // _dword_4D5E00_is_multiplayer
    offset = x86.test_edx_edx(offset);
    offset = x86.pop_edx(offset);
    offset = x86.jz(offset, 0x47B0C0);
    offset = x86.retn(offset);

    // Install it by patching call at 0x47B5AF
    _ = mem.write(0x47B5AF + 1, u32, memory_offset_collision_code - (0x47B5AF + 5));

    return offset;
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
        if (s.mp.get("patch_netplay", bool)) {
            const r100 = s.mp.get("netplay_r100", bool);
            const guid = s.mp.get("netplay_guid", bool);
            const traction: u8 = if (r100) 3 else 5;
            var upgrade_lv: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
            var upgrade_hp: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
            const upgrade_lv_ptr: *[7]u8 = @ptrCast(&upgrade_lv);
            const upgrade_hp_ptr: *[7]u8 = @ptrCast(&upgrade_hp);
            off = PatchNetworkUpgrades(off, upgrade_lv_ptr, upgrade_hp_ptr, guid);
            off = PatchNetworkCollisions(off, guid);
        }
    }
    return off;
}
