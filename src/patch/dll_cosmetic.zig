const Self = @This();

const std = @import("std");

const GlobalState = @import("global.zig").GlobalState;
const GlobalVTable = @import("global.zig").GlobalVTable;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");

const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

// TODO:
//- general: ?? rainbow ui (timer, pos, laps, but not labels)
//- general: ?? rainbow labels
//- general: ?? custom static color for all of the above

// COLOR CHANGES

fn PatchHudTimerColRotate() void { // 0xFFFFFFBE
    const col = struct {
        const min: u8 = 95;
        const max: u8 = 255;
        var rgb: [3]u8 = .{ 255, 95, 95 };
        var i: u8 = 0;
        var n: u8 = 1;
        fn update() void {
            n = (i + 1) % 3;
            if (rgb[i] == min and rgb[n] == max) i = n;
            n = (i + 1) % 3;
            if (rgb[i] == max and rgb[n] < max) {
                rgb[n] += 1;
            } else {
                rgb[i] -= 1;
            }
        }
    };
    col.update();
    _ = mem.write(0x460E5E, u8, col.rgb[0]); // B, 255
    _ = mem.write(0x460E60, u8, col.rgb[1]); // G, 255
    _ = mem.write(0x460E62, u8, col.rgb[2]); // R, 255
}

fn PatchHudTimerCol(rgba: u32) void { // 0xFFFFFFBE
    _ = mem.write(0x460E5C, u8, @as(u8, @truncate(rgba))); // A, 190
    _ = mem.write(0x460E5E, u8, @as(u8, @truncate(rgba >> 8))); // B, 255
    _ = mem.write(0x460E60, u8, @as(u8, @truncate(rgba >> 16))); // G, 255
    _ = mem.write(0x460E62, u8, @as(u8, @truncate(rgba >> 24))); // R, 255
}

fn PatchHudTimerLabelCol(rgba: u32) void { // 0xFFFFFFBE
    _ = mem.write(0x460E8C, u8, @as(u8, @truncate(rgba))); // A, 190
    _ = mem.write(0x460E8E, u8, @as(u8, @truncate(rgba >> 8))); // B, 255
    _ = mem.write(0x460E90, u8, @as(u8, @truncate(rgba >> 16))); // G, 255
    _ = mem.write(0x460E92, u8, @as(u8, @truncate(rgba >> 24))); // R, 255
}

// SWE1R-PATCHER STUFF

fn PatchTextureTable(memory_offset: usize, table_offset: usize, code_begin_offset: usize, code_end_offset: usize, width: u32, height: u32, filename: []const u8) usize {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

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

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return "Cosmetic";
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return "0.0.1";
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = initialized;
    var off = gs.patch_offset;
    if (gv.SettingGetB("multiplayer", "patch_fonts").?) {
        off = PatchTextureTable(off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
        off = PatchTextureTable(off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
        off = PatchTextureTable(off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
        off = PatchTextureTable(off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
        off = PatchTextureTable(off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
    }
    if (gv.SettingGetB("multiplayer", "patch_audio").?) {
        const sample_rate: u32 = 22050 * 2;
        const bits_per_sample: u8 = 16;
        const stereo: bool = true;
        PatchAudioStreamQuality(sample_rate, bits_per_sample, stereo);
    }
    if (gv.SettingGetB("multiplayer", "patch_tga_loader").?) {
        off = PatchSpriteLoaderToLoadTga(off);
    }
    if (gv.SettingGetB("multiplayer", "patch_trigger_display").?) {
        off = PatchTriggerDisplay(off);
    }
    gs.patch_offset = off;
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = gs;
    _ = initialized;
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

// HOOKS

export fn TextRenderB(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = initialized;
    _ = gs;
    if (gv.SettingGetB("general", "rainbow_timer_enable").?) {
        PatchHudTimerColRotate();
    }
}
