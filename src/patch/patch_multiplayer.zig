const PatchMultiplayer = @This();

const std = @import("std");
const user32 = std.os.windows.user32;

const assert = std.debug.assert;

const VirtualAlloc = std.os.windows.VirtualAlloc;
const VirtualFree = std.os.windows.VirtualFree;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const MEM_RELEASE = std.os.windows.MEM_RELEASE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;

const MessageBoxA = user32.MessageBoxA;
const MB_OK = user32.MB_OK;
const MB_ICONINFORMATION = user32.MB_ICONINFORMATION;

const mem = @import("util/memory.zig");

// FIXME: not crashing for now, but need to address virtualalloc size
// NOTE: probably need to investigate the actual data in memory
//   and use a real img format, without manually building the file.
//   but, what it outputs now looks right, just not sure if it's the whole data for each file
// FIXME: handle FileAlreadyExists case (not sure best approach yet)
pub fn DumpTexture(alloc: std.mem.Allocator, offset: usize, unk0: u8, unk1: u8, width: u32, height: u32, filename: []const u8) void {
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
    var texture = VirtualAlloc(null, texture_size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE) catch unreachable; // FIXME: error handling
    defer VirtualFree(texture, 0, MEM_RELEASE);
    const texture_slice = @as([*]u8, @ptrCast(texture))[0..texture_size];
    mem.read_bytes(offset + 4, texture, texture_size);

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
pub fn DumpTextureTable(alloc: std.mem.Allocator, offset: usize, unk0: u8, unk1: u8, width: u32, height: u32, filename: []const u8) u32 {
    // Get size of the table
    const count: u32 = mem.read(offset + 0, u32); // NOTE: exe unnecessary, just read ram

    // Loop over elements and dump each
    var offsets = VirtualAlloc(null, count * 4, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE) catch unreachable; // FIXME: error handling
    defer VirtualFree(offsets, 0, MEM_RELEASE);
    const offsets_slice = @as([*]align(1) u32, @ptrCast(offsets))[0..count];
    mem.read_bytes(offset + 4, offsets, count * 4);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const filename_i = std.fmt.allocPrintZ(alloc, "annodue/textures/{s}_{d}.ppm", .{ filename, i }) catch unreachable; // FIXME: error handling
        DumpTexture(alloc, offsets_slice[i], unk0, unk1, width, height, filename_i);
    }
    return count;
}

pub fn PatchTextureTable(alloc: std.mem.Allocator, memory_offset: usize, table_offset: usize, code_begin_offset: usize, code_end_offset: usize, width: u32, height: u32, filename: []const u8) usize {
    var offset: usize = memory_offset;
    offset = mem.nop_align(offset, 16);

    // Original code takes u8 dimension args, so we use our own code that takes u32
    const cave_memory_offset: usize = offset;

    // Patches the arguments for the texture loader
    offset = mem.push_u32(offset, height);
    offset = mem.push_u32(offset, width);
    offset = mem.push_u32(offset, height);
    offset = mem.push_u32(offset, width);
    offset = mem.jmp(offset, code_end_offset);

    // Detour original code to ours
    var hack_offset: usize = mem.jmp(code_begin_offset, cave_memory_offset);
    _ = mem.nop_until(hack_offset, code_end_offset);

    // Get number of textures in the table
    const count: u32 = mem.read(table_offset + 0, u32);

    // Have a buffer for pixeldata
    const texture_size: u32 = width * height * 4 / 8;
    var buffer = VirtualAlloc(null, texture_size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE) catch unreachable; // FIXME: error handling
    defer VirtualFree(buffer, 0, MEM_RELEASE);
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
        offset = mem.write_bytes(offset, buffer, texture_size);

        // Patch the table entry
        //const texture_old: usize = mem.read(table_offset + 4 + i * 4, u32);
        _ = mem.write(table_offset + 4 + i * 4, u32, texture_new);
        //printf("%d: 0x%X -> 0x%X\n", i, texture_old, texture_new);
    }

    return offset;
}

pub fn SWAP(a: *u8, b: *u8) void {
    if (a.* ^ b.* > 0) {
        a.* ^= b.*;
        b.* ^= a.*;
        a.* ^= b.*;
    }
}

// WARNING: not tested
// FIXME: causes crash on startup
pub fn ModifyNetworkGuid(data: [*]u8, size: usize) void {
    // RC4 hash
    const state = struct {
        var s: [256]u8 = undefined;
        var initialized: bool = false;
    };
    if (!state.initialized) {
        var i: u8 = 0;
        while (i < 256) : (i += 1) {
            state.s[i] = i;
        }
        state.initialized = true;
    }

    assert(size <= 256);
    const data_bytes: []u8 = data[0..size];
    var i: usize = 0;
    var j: usize = 0;
    while (i < 256) : (i += 1) {
        j += state.s[i] + data_bytes[i % size];
        SWAP(&state.s[i], &state.s[j]);
    }

    var k_i: u8 = 0;
    var k_j: u8 = 0;
    var k_s: [256]u8 = undefined;
    @memcpy(&k_s, &state.s);
    i = 0;
    while (i < 16) : (i += 1) {
        k_i += 1;
        k_j += k_s[k_i];
        SWAP(&k_s[k_i], &k_s[k_j]);
        var rc4_output: u8 = k_s[(k_s[k_i] + k_s[k_j]) & 0xFF];
        _ = mem.write(0x4AF9B0 + i, u8, rc4_output);
    }

    // Overwrite the first 2 byte with a version index, so we have room
    // to fix the algorithm if we have messed up
    _ = mem.write(0x4AF9B0 + 0, u16, 0x00000000);
}

// WARNING: not tested
pub fn PatchNetworkUpgrades(memory_offset: usize, upgrade_levels: *[7]u8, upgrade_healths: *[7]u8, patch_guid: bool) usize {
    if (patch_guid) {
        ModifyNetworkGuid(@constCast("Upgrades"), 8);
        ModifyNetworkGuid(upgrade_levels, 7);
        ModifyNetworkGuid(upgrade_healths, 7);
    }

    // Now do the actual upgrade for menus
    _ = mem.write(0x45CFC6, u8, 0x05); // levels
    _ = mem.write(0x45CFCB, u8, 0xFF); // healths

    //FIXME: Upgrade network player creation
    // 0x45B725 vs 0x45B9FF
    //lea     edx, [esp+1Ch+upgrade_health]
    //lea     eax, [esp+1Ch+upgrade_level]
    //push    edx             ; upgrade_healths
    //push    eax             ; upgrade_levels
    //push    ebp             ; handling_in
    //push    offset handling_out ; handling_out
    //mov     [esp+esi+2Ch+upgrade_health], cl
    //call    _sub_449D00_generate_upgraded_handling_table_data

    var offset: usize = memory_offset;

    // Place upgrade data in memory

    const memory_offset_upgrade_levels: usize = offset;
    offset = mem.write(offset, @TypeOf(upgrade_levels.*), upgrade_levels.*);

    const memory_offset_upgrade_healths: usize = offset;
    offset = mem.write(offset, @TypeOf(upgrade_healths.*), upgrade_healths.*);

    // Now inject the code

    const memory_offset_upgrade_code: usize = offset;

    offset = mem.push_edx(offset);
    offset = mem.push_eax(offset);
    offset = mem.push_u32(offset, memory_offset_upgrade_healths);
    offset = mem.push_u32(offset, memory_offset_upgrade_levels);

    offset = mem.push_esi(offset);
    offset = mem.push_edi(offset);
    offset = mem.call(offset, 0x449D00);

    offset = mem.add_esp8(offset, 0x10);

    offset = mem.pop_eax(offset);
    offset = mem.pop_edx(offset);

    offset = mem.retn(offset);

    // Install it by jumping from 0x45B765 and returning to 0x45B76C
    _ = mem.write(0x45B765 + 0, u8, 0xE8);
    _ = mem.write(0x45B765 + 1, u32, memory_offset_upgrade_code - (0x45B765 + 5));
    _ = mem.write(0x45B765 + 5, u8, 0x90);
    _ = mem.write(0x45B765 + 6, u8, 0x90);

    return memory_offset;
}

// WARNING: not tested
pub fn PatchNetworkCollisions(memory_offset: usize, patch_guid: bool) usize {
    // Disable collision between network players
    if (patch_guid) {
        ModifyNetworkGuid(@constCast("Collisions"), 10);
    }

    var offset: usize = memory_offset;
    const memory_offset_collision_code: usize = memory_offset;

    // Inject new code
    offset = mem.push_edx(offset);
    offset = mem.mov_edx(offset, 0x4D5E00); // _dword_4D5E00_is_multiplayer
    offset = mem.test_edx_edx(offset);
    offset = mem.pop_edx(offset);
    offset = mem.jz(offset, 0x47B0C0);
    offset = mem.retn(offset);

    // Install it by patching call at 0x47B5AF
    _ = mem.write(0x47B5AF + 1, u32, memory_offset_collision_code - (0x47B5AF + 5));

    return offset;
}

// WARNING: not tested
pub fn PatchAudioStreamQuality(memory_offset: usize, sample_rate: u32, bits_per_sample: u8, stereo: bool) usize {
    var offset: usize = memory_offset;

    // Calculate a fitting buffer-size
    const buffer_stereo: u32 = if (stereo) 2 else 1;
    const buffer_size: u32 = 2 * sample_rate * (bits_per_sample / 8) * buffer_stereo;

    // Patch audio stream source setting
    offset = mem.write(0x423215, u32, buffer_size);
    offset = mem.write(0x42321A, u8, bits_per_sample);
    offset = mem.write(0x42321E, u32, sample_rate);

    // Patch audio stream buffer chunk size
    offset = mem.write(0x423549, u32, buffer_size / 2);
    offset = mem.write(0x42354E, u32, buffer_size / 2);
    offset = mem.write(0x423555, u32, buffer_size / 2);

    return offset;
}

// WARNING: not tested
pub fn PatchSpriteLoaderToLoadTga(memory_offset: usize) usize {
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
    offset = mem.add_esp32(offset, 0x4 + 0x400);
    offset = mem.retn(offset);

    // Start of actual code
    const offset_tga_loader_code: usize = offset;

    // Read the sprite_index from stack
    //  -> mov     eax, [esp+4]
    offset = mem.write(offset, u8, 0x8B);
    offset = mem.write(offset, u8, 0x44);
    offset = mem.write(offset, u8, 0x24);
    offset = mem.write(offset, u8, 0x04);

    // Make room for sprintf buffer and keep the pointer in edx
    offset = mem.add_esp32(offset, @bitCast(@as(i32, -0x400)));
    offset = mem.mov_edx_esp(offset);

    // Generate the path, keep sprite_index on stack as we'll keep using it
    offset = mem.push_eax(offset); // (sprite_index)
    offset = mem.push_u32(offset, offset_tga_path); // (fmt)
    offset = mem.push_edx(offset); // (buffer)
    offset = mem.call(offset, 0x49EB80); // sprintf
    offset = mem.pop_edx(offset); // (buffer)
    offset = mem.add_esp32(offset, 0x4);

    // Attempt to load the TGA, then remove path from stack
    offset = mem.push_edx(offset); // (buffer)
    offset = mem.call(offset, 0x4114D0); // load_sprite_from_tga_and_add_loaded_sprite
    offset = mem.add_esp32(offset, 0x4);

    // Check if the load failed
    offset = mem.test_eax_eax(offset);
    offset = mem.jnz(offset, offset_load_success);

    // Load failed, so load the original sprite (sprite-index still on stack)
    offset = mem.call(offset, 0x446CA0); // load_sprite_internal

    offset = mem.jmp(offset, offset_finish);

    // Install it by jumping from 0x446FB0 (and we'll return directly)
    _ = mem.jmp(0x446FB0, offset_tga_loader_code);

    return offset;
}

pub fn PatchTriggerDisplay(memory_offset: usize) usize {
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
    offset = mem.add_esp32(offset, @bitCast(@as(i32, -0x400))); // add    esp, -400h
    offset = mem.mov_edx_esp(offset);

    // Generate the string we'll display
    offset = mem.push_eax(offset); // (trigger index)
    offset = mem.push_u32(offset, offset_trigger_string); // (fmt)
    offset = mem.push_edx(offset); // (buffer)
    offset = mem.call(offset, 0x49EB80); // sprintf
    offset = mem.pop_edx(offset); // (buffer)
    offset = mem.add_esp32(offset, 0x8);

    // Display a message
    offset = mem.push_u32(offset, @bitCast(trigger_string_display_duration));
    offset = mem.push_edx(offset); // (buffer)
    offset = mem.call(offset, 0x44FCE0);
    offset = mem.add_esp32(offset, 0x8);

    // Pop the string buffer off of the stack
    offset = mem.add_esp32(offset, 0x400);

    // Jump to the real function to run the trigger
    offset = mem.jmp(offset, 0x47CE60);

    // Install it by replacing the call destination (we'll jump to the real one)
    _ = mem.call(0x476E80, offset_trigger_code);

    return offset;
}
