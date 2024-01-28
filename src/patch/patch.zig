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

const ver_major: u32 = 0;
const ver_minor: u32 = 0;
const ver_patch: u32 = 1;

const mem = @import("util/memory.zig");

fn PtrMessage(alloc: std.mem.Allocator, ptr: usize, label: []const u8) void {
    var buf = std.fmt.allocPrintZ(alloc, "{s}: 0x{x}", .{ label, ptr }) catch unreachable;
    _ = MessageBoxA(null, buf, "patch.dll", MB_OK);
}

const patch_size: u32 = 4 * 1024 * 1024;
const USE_PATCHED_GUID = true;
const USE_PATCHED_NETPLAY = true;
const USE_PATCHED_AUDIO = true;
const USE_PATCHED_FONTS = true;
const DUMP_FONTS = true;
const USE_TRIGGER_DISPLAY = true;
const USE_TGA_LOADER = true;
const USE_R100 = true;

fn PatchDeathSpeed(min: f32, drop: f32) void {
    //0x4C7BB8	4	DeathSpeedMin	float	325.0		SWEP1RCR.EXE+0x0C7BB8
    _ = mem.write(0x4C7BB8, f32, min);
    //0x4C7BBC	4	DeathSpeedDrop	float	140.0		SWEP1RCR.EXE+0x0C7BBC
    _ = mem.write(0x4C7BBC, f32, drop);
}

// WARNING: not tested
fn DumpTexture(alloc: std.mem.Allocator, offset: usize, unk0: u8, unk1: u8, width: u32, height: u32, filename: []const u8) void {
    // Presumably the format information?
    assert(unk0 == 3);
    assert(unk1 == 0);

    const out = std.fs.cwd().openFile(filename, .{ .mode = .write_only }) catch unreachable; // FIXME: error handling
    defer out.close();
    var out_pos: usize = 0;
    const out_head = std.fmt.allocPrintZ(alloc, "P3\n{d} {d}\n15\n", .{ width, height }) catch unreachable; // FIXME: error handling
    out_pos = out.pwrite(out_head, out_pos) catch unreachable; // FIXME: error handling

    // Copy the pixel data
    const texture_size = width * height * 4 / 8;
    var texture = VirtualAlloc(null, texture_size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE) catch unreachable; // FIXME: error handling
    defer VirtualFree(texture, 0, MEM_RELEASE);
    const texture_slice = @as([*]u8, @ptrCast(texture))[0..texture_size];
    mem.read_bytes(offset + 4, texture, texture_size);
    var i: usize = 0;
    while (i < width * height * 2) {
        const v: u8 = ((texture_slice[i / 2] << @as(u3, @truncate((i % 2) * 4))) & 0xF0) >> 4;
        const out_frag = std.fmt.allocPrintZ(alloc, "{d} {d} {d}\n", .{ v, v, v }) catch unreachable; // FIXME: error handling
        out_pos = out.pwrite(out_frag, out_pos) catch unreachable; // FIXME: error handling
        i += 1;
    }
}

// WARNING: not tested
fn DumpTextureTable(alloc: std.mem.Allocator, offset: usize, unk0: u8, unk1: u8, width: u32, height: u32, filename: [*:0]const u8) u32 {
    // Get size of the table
    const count: u32 = mem.read(offset + 0, u32); // NOTE: exe unnecessary, just read ram

    // Loop over elements and dump each
    var offsets = VirtualAlloc(null, count * 4, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE) catch unreachable; // FIXME: error handling
    defer VirtualFree(offsets, 0, MEM_RELEASE);
    const offsets_slice = @as([*]align(1) u32, @ptrCast(offsets))[0..count];
    mem.read_bytes(offset + 4, offsets, count * 4);
    var i: usize = 0;
    while (i < count) {
        const filename_i = std.fmt.allocPrintZ(alloc, "annodue/textures/{s}_{d}.ppm", .{ filename, i }) catch unreachable; // FIXME: error handling
        DumpTexture(alloc, offsets_slice[i], unk0, unk1, width, height, filename_i);
        i += 1;
    }
    return count;
}

// WARNING: not tested
fn PatchTextureTable(alloc: std.mem.Allocator, memory_offset: usize, table_offset: usize, code_begin_offset: usize, code_end_offset: usize, width: u32, height: u32, filename: [*:0]const u8) usize {
    var offset: usize = memory_offset;

    if (true) {
        offset = mem.nop_align(offset, 16);
    }

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
    while (i < count) {
        // Load input texture to buffer
        var path = std.fmt.allocPrintZ(alloc, "annodue/textures/{s}_{d}_test.data", .{ filename, i }) catch unreachable; // FIXME: error handling

        //printf("Loading '%s'\n", path);
        const file = std.fs.cwd().openFile(path, .{}) catch unreachable; // FIXME: error handling
        defer file.close();
        var file_pos: usize = 0;
        @memset(buffer_slice, 0x00);
        var j: u32 = 0;
        while (j < texture_size * 2) {
            var pixel: [2]u8 = undefined; // GIMP only exports Gray + Alpha..
            file_pos = file.pread(&pixel, file_pos) catch unreachable; // FIXME: error handling
            buffer_slice[j / 2] |= (pixel[0] & 0xF0) >> @as(u3, @truncate((j % 2) * 4));
            j += 1;
        }

        // Write pixel data to game
        const texture_new: usize = offset;
        offset = mem.write_bytes(offset, buffer, texture_size); // FIXME: does this work? issue is original memory is pointer-accessed, but write() takes data

        // Patch the table entry
        const texture_old: usize = mem.read(table_offset + 4 + i * 4, u32);
        _ = texture_old;
        _ = texture_old;
        _ = mem.write(table_offset + 4 + i * 4, u32, texture_new);
        //printf("%d: 0x%X -> 0x%X\n", i, texture_old, texture_new);
        i += 1;
    }
    //free(buffer);

    return offset;
}

fn SWAP(a: *u8, b: *u8) void {
    if (a.* ^ b.* > 0) {
        a.* ^= b.*;
        b.* ^= a.*;
        a.* ^= b.*;
    }
}

// WARNING: not tested
fn ModifyNetworkGuid(data: [*]u8, size: usize) void {
    // RC4 hash
    const state = struct {
        var s: [256]u8 = undefined;
        var initialized: bool = false;
    };
    if (!state.initialized) {
        var i: u8 = 0;
        while (i < 256) {
            state.s[i] = i;
            i += 1;
        }
        state.initialized = true;
    }

    assert(size <= 256);
    const data_bytes: []u8 = data[0..size];
    var i: usize = 0;
    var j: usize = 0;
    while (i < 256) {
        j += state.s[i] + data_bytes[i % size];
        SWAP(&state.s[i], &state.s[j]);
        i += 1;
    }

    var k_i: u8 = 0;
    var k_j: u8 = 0;
    var k_s: [256]u8 = undefined;
    @memcpy(&k_s, &state.s);
    i = 0;
    while (i < 16) {
        k_i += 1;
        k_j += k_s[k_i];
        SWAP(&k_s[k_i], &k_s[k_j]);
        var rc4_output: u8 = k_s[(k_s[k_i] + k_s[k_j]) & 0xFF];
        _ = mem.write(0x4AF9B0 + i, u8, rc4_output);
        i += 1;
    }

    // Overwrite the first 2 byte with a version index, so we have room
    // to fix the algorithm if we have messed up
    _ = mem.write(0x4AF9B0 + 0, u16, 0x00000000);
}

// WARNING: not tested
fn PatchNetworkUpgrades(memory_offset: usize, upgrade_levels: *[7]u8, upgrade_healths: *[7]u8) usize {
    if (USE_PATCHED_GUID) {
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
fn PatchNetworkCollisions(memory_offset: usize) usize {
    // Disable collision between network players
    if (USE_PATCHED_GUID) {
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
fn PatchAudioStreamQuality(memory_offset: usize, sample_rate: u32, bits_per_sample: u8, stereo: bool) usize {
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

export fn Patch() void {
    var offset: usize = @intFromPtr(VirtualAlloc(null, patch_size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE) catch unreachable);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    PatchDeathSpeed(650, 25);

    // swe1r-patcher stuff

    if (DUMP_FONTS) {
        // This is a debug feature to dump the original font textures
        _ = DumpTextureTable(alloc, 0x4BF91C, 3, 0, 64, 128, "font0");
        _ = DumpTextureTable(alloc, 0x4BF7E4, 3, 0, 64, 128, "font1");
        _ = DumpTextureTable(alloc, 0x4BF84C, 3, 0, 64, 128, "font2");
        _ = DumpTextureTable(alloc, 0x4BF8B4, 3, 0, 64, 128, "font3");
        _ = DumpTextureTable(alloc, 0x4BF984, 3, 0, 64, 128, "font4");
    }

    if (USE_PATCHED_FONTS) {
        offset = PatchTextureTable(alloc, offset, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
        offset = PatchTextureTable(alloc, offset, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
        offset = PatchTextureTable(alloc, offset, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
        offset = PatchTextureTable(alloc, offset, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
        offset = PatchTextureTable(alloc, offset, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
    }

    if (USE_PATCHED_NETPLAY) {
        const traction = if (USE_R100) 3 else 5;
        var upgrade_levels: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
        var upgrade_healths: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
        offset = PatchNetworkUpgrades(offset, @ptrCast(&upgrade_levels), @ptrCast(&upgrade_healths));
        offset = PatchNetworkCollisions(offset);
    }

    if (USE_PATCHED_AUDIO) {
        const sample_rate: u32 = 22050 * 2;
        const bits_per_sample: u8 = 16;
        const stereo: bool = true;
        offset = PatchAudioStreamQuality(offset, sample_rate, bits_per_sample, stereo);
    }

    if (USE_TGA_LOADER) {
        offset = PatchSpriteLoaderToLoadTga(offset);
    }

    if (USE_TRIGGER_DISPLAY) {
        offset = PatchTriggerDisplay(offset);
    }

    if (false) {
        var mb_title = std.fmt.allocPrintZ(alloc, "Annodue {d}.{d}.{d}", .{
            ver_major,
            ver_minor,
            ver_patch,
        }) catch unreachable;
        var mb_launch = "Patching SWE1R...";
        _ = MessageBoxA(null, mb_launch, mb_title, MB_OK);
    }
}
