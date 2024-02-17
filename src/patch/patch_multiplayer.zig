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

fn PatchTextureTable(alloc: std.mem.Allocator, memory_offset: usize, table_offset: usize, code_begin_offset: usize, code_end_offset: usize, width: u32, height: u32, filename: []const u8) usize {
    var offset: usize = memory_offset;
    offset = x86.nop_align(offset, 16);

    // Original code takes u8 dimension args, so we use our own code that takes u32
    const cave_memory_offset: usize = offset;

    // Patches the arguments for the texture loader
    offset = x86.push_u32(offset, height);
    offset = x86.push_u32(offset, width);
    offset = x86.push_u32(offset, height);
    offset = x86.push_u32(offset, width);
    offset = x86.jmp(offset, code_end_offset);

    // Detour original code to ours
    var hack_offset: usize = x86.jmp(code_begin_offset, cave_memory_offset);
    _ = x86.nop_until(hack_offset, code_end_offset);

    // Get number of textures in the table
    const count: u32 = mem.read(table_offset + 0, u32);

    // Have a buffer for pixeldata
    const texture_size: u32 = width * height * 4 / 8;
    var buffer = alloc.alloc(u8, texture_size) catch unreachable;
    defer alloc.free(buffer);
    const buffer_slice = @as([*]u8, @ptrCast(buffer))[0..texture_size];

    // Loop over all textures
    var i: usize = 0;
    while (i < count) : (i += 1) {
        // Load input texture to buffer
        var path = std.fmt.allocPrintZ(alloc, "annodue/textures/{s}_{d}_test.data", .{ filename, i }) catch unreachable; // FIXME: error handling

        const file = std.fs.cwd().openFile(path, .{}) catch unreachable; // FIXME: error handling
        defer file.close();
        var file_pos: usize = 0;
        @memset(buffer_slice, 0x00);
        var j: u32 = 0;
        while (j < texture_size * 2) : (j += 1) {
            var pixel: [2]u8 = undefined; // GIMP only exports Gray + Alpha..
            file_pos += file.pread(&pixel, file_pos) catch unreachable; // FIXME: error handling
            buffer_slice[j / 2] |= (pixel[0] & 0xF0) >> @as(u3, @truncate((j % 2) * 4));
        }

        // Write pixel data to game
        const texture_new: usize = offset;
        offset = mem.write_bytes(offset, &buffer[0], texture_size);

        // Patch the table entry
        //const texture_old: usize = mem.read(table_offset + 4 + i * 4, u32);
        _ = mem.write(table_offset + 4 + i * 4, u32, texture_new);
        //printf("%d: 0x%X -> 0x%X\n", i, texture_old, texture_new);
    }

    return offset;
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

// FIXME: crashes, not sure why because the memory written should be identical
// to swe1r-patcher, yet that doesn't crash
fn PatchAudioStreamQuality(sample_rate: u32, bits_per_sample: u8, stereo: bool) void {
    // Calculate a fitting buffer-size
    const buffer_stereo: u32 = if (stereo) 2 else 1;
    const buffer_size: u32 = 2 * sample_rate * (bits_per_sample / 8) * buffer_stereo;

    // Patch audio stream source setting
    _ = mem.write(0x423215, u32, buffer_size);
    _ = mem.write(0x42321A, u8, bits_per_sample);
    _ = mem.write(0x42321E, u32, sample_rate);

    // Patch audio stream buffer chunk size
    _ = mem.write(0x423549, u32, buffer_size / 2);
    _ = mem.write(0x42354E, u32, buffer_size / 2);
    _ = mem.write(0x423555, u32, buffer_size / 2);
}

// WARNING: not tested
fn PatchSpriteLoaderToLoadTga(memory_offset: usize) usize {
    // Replace the sprite loader with a version that checks for "data\\images\\sprite-%d.tga"
    var offset: usize = memory_offset;

    // Write the path we want to use to the binary
    const tga_path = "data\\sprites\\sprite-%d.tga";

    const offset_tga_path: usize = offset;
    offset = mem.write(offset, @TypeOf(tga_path.*), tga_path.*);

    // FIXME: load_success: Yay! Shift down size, to compensate for higher resolution
    const offset_load_success: usize = offset;

    // TODO: figure out what this asm means and make macros
    // Shift the width and height of the sprite to the right
    offset = mem.write(offset, u8, 0x66);
    offset = mem.write(offset, u8, 0xC1);
    offset = mem.write(offset, u8, 0x68);
    offset = mem.write(offset, u8, 0);
    offset = mem.write(offset, u8, 1);

    offset = mem.write(offset, u8, 0x66);
    offset = mem.write(offset, u8, 0xC1);
    offset = mem.write(offset, u8, 0x68);
    offset = mem.write(offset, u8, 2);
    offset = mem.write(offset, u8, 2);

    offset = mem.write(offset, u8, 0x66);
    offset = mem.write(offset, u8, 0xC1);
    offset = mem.write(offset, u8, 0x68);
    offset = mem.write(offset, u8, 14);
    offset = mem.write(offset, u8, 2);

    // Get address of page and repeat steps
    offset = mem.write(offset, u8, 0x8B);
    offset = mem.write(offset, u8, 0x50);
    offset = mem.write(offset, u8, 16);

    offset = mem.write(offset, u8, 0x66);
    offset = mem.write(offset, u8, 0xC1);
    offset = mem.write(offset, u8, 0x6A);
    offset = mem.write(offset, u8, 0);
    offset = mem.write(offset, u8, 1);

    offset = mem.write(offset, u8, 0x66);
    offset = mem.write(offset, u8, 0xC1);
    offset = mem.write(offset, u8, 0x6A);
    offset = mem.write(offset, u8, 2);
    offset = mem.write(offset, u8, 2);

    // Get address of texture and repeat steps

    //0:  8b 50 10                mov    edx,DWORD PTR [eax+0x10]
    //3:  66 c1 6a 02 02          shr    WORD PTR [edx+0x2],0x2

    // finish: Clear stack and return
    const offset_finish: usize = offset;
    offset = x86.add_esp32(offset, 0x4 + 0x400);
    offset = x86.retn(offset);

    // Start of actual code
    const offset_tga_loader_code: usize = offset;

    // Read the sprite_index from stack
    //  -> mov     eax, [esp+4]
    offset = mem.write(offset, u8, 0x8B);
    offset = mem.write(offset, u8, 0x44);
    offset = mem.write(offset, u8, 0x24);
    offset = mem.write(offset, u8, 0x04);

    // Make room for sprintf buffer and keep the pointer in edx
    offset = x86.add_esp32(offset, @bitCast(@as(i32, -0x400)));
    offset = x86.mov_edx_esp(offset);

    // Generate the path, keep sprite_index on stack as we'll keep using it
    offset = x86.push_eax(offset); // (sprite_index)
    offset = x86.push_u32(offset, offset_tga_path); // (fmt)
    offset = x86.push_edx(offset); // (buffer)
    offset = x86.call(offset, 0x49EB80); // sprintf
    offset = x86.pop_edx(offset); // (buffer)
    offset = x86.add_esp32(offset, 0x4);

    // Attempt to load the TGA, then remove path from stack
    offset = x86.push_edx(offset); // (buffer)
    offset = x86.call(offset, 0x4114D0); // load_sprite_from_tga_and_add_loaded_sprite
    offset = x86.add_esp32(offset, 0x4);

    // Check if the load failed
    offset = x86.test_eax_eax(offset);
    offset = x86.jnz(offset, offset_load_success);

    // Load failed, so load the original sprite (sprite-index still on stack)
    offset = x86.call(offset, 0x446CA0); // load_sprite_internal

    offset = x86.jmp(offset, offset_finish);

    // Install it by jumping from 0x446FB0 (and we'll return directly)
    _ = x86.jmp(0x446FB0, offset_tga_loader_code);

    return offset;
}

fn PatchTriggerDisplay(memory_offset: usize) usize {
    var offset = memory_offset;

    // Display triggers
    const trigger_string = "Trigger %d activated";
    const trigger_string_display_duration: f32 = 3.0;

    var offset_trigger_string = offset;
    offset = mem.write(offset, @TypeOf(trigger_string.*), trigger_string.*);

    var offset_trigger_code: u32 = offset;

    // Read the trigger from stack
    offset = mem.write(offset, u8, 0x8B); // mov    eax, [esp+4]
    offset = mem.write(offset, u8, 0x44);
    offset = mem.write(offset, u8, 0x24);
    offset = mem.write(offset, u8, 0x04);

    // Get pointer to section 8
    offset = mem.write(offset, u8, 0x8B); // 8b 40 4c  ->  mov    eax,DWORD PTR [eax+0x4c]
    offset = mem.write(offset, u8, 0x40);
    offset = mem.write(offset, u8, 0x4C);

    // Read the section8.trigger_action field
    offset = mem.write(offset, u8, 0x0F); // 0f b7 40 24  ->  movzx    eax, WORD PTR [eax+0x24]
    offset = mem.write(offset, u8, 0xB7);
    offset = mem.write(offset, u8, 0x40);
    offset = mem.write(offset, u8, 0x24);

    // Make room for sprintf buffer and keep the pointer in edx
    offset = x86.add_esp32(offset, @bitCast(@as(i32, -0x400))); // add    esp, -400h
    offset = x86.mov_edx_esp(offset);

    // Generate the string we'll display
    offset = x86.push_eax(offset); // (trigger index)
    offset = x86.push_u32(offset, offset_trigger_string); // (fmt)
    offset = x86.push_edx(offset); // (buffer)
    offset = x86.call(offset, 0x49EB80); // sprintf
    offset = x86.pop_edx(offset); // (buffer)
    offset = x86.add_esp32(offset, 0x8);

    // Display a message
    offset = x86.push_u32(offset, @bitCast(trigger_string_display_duration));
    offset = x86.push_edx(offset); // (buffer)
    offset = x86.call(offset, 0x44FCE0);
    offset = x86.add_esp32(offset, 0x8);

    // Pop the string buffer off of the stack
    offset = x86.add_esp32(offset, 0x400);

    // Jump to the real function to run the trigger
    offset = x86.jmp(offset, 0x47CE60);

    // Install it by replacing the call destination (we'll jump to the real one)
    _ = x86.call(0x476E80, offset_trigger_code);

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
        if (s.mp.get("patch_fonts", bool)) {
            off = PatchTextureTable(alloc, off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
            off = PatchTextureTable(alloc, off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
            off = PatchTextureTable(alloc, off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
            off = PatchTextureTable(alloc, off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
            off = PatchTextureTable(alloc, off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
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
        if (s.mp.get("patch_audio", bool)) {
            const sample_rate: u32 = 22050 * 2;
            const bits_per_sample: u8 = 16;
            const stereo: bool = true;
            PatchAudioStreamQuality(sample_rate, bits_per_sample, stereo);
        }
        if (s.mp.get("patch_tga_loader", bool)) {
            off = PatchSpriteLoaderToLoadTga(off);
        }
        if (s.mp.get("patch_trigger_display", bool)) {
            off = PatchTriggerDisplay(off);
        }
    }
    return off;
}
