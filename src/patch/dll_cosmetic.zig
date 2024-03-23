const Self = @This();

const std = @import("std");

const GlobalSt = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");

const crot = @import("util/color.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

// TODO:
//- general: ?? custom static color as an option for the rainbow stuff?

const PLUGIN_NAME: [*:0]const u8 = "Cosmetic";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const CosmeticState = struct {
    var rb_enable: bool = false;
    var rb_value_enable: bool = false;
    var rb_label_enable: bool = false;
    var rb_speed_enable: bool = false;
    var rb_value = crot.RotatingRGB.new(95, 255, 0);
    var rb_label = crot.RotatingRGB.new(95, 255, 1);
    var rb_speed = crot.RotatingRGB.new(95, 255, 2);
};

// COLOR CHANGES

fn PatchHudColRotate(v: bool, l: bool, s: bool) void {
    CosmeticState.rb_value.update();
    CosmeticState.rb_label.update();
    CosmeticState.rb_speed.update();
    if (v) {
        crot.PatchRgbArgs(0x460E5D, CosmeticState.rb_value.get());
        crot.PatchRgbArgs(0x460FB1, CosmeticState.rb_value.get());
        crot.PatchRgbArgs(0x461045, CosmeticState.rb_value.get());
    }
    if (l) {
        crot.PatchRgbArgs(0x460E8D, CosmeticState.rb_label.get());
        crot.PatchRgbArgs(0x460FE3, CosmeticState.rb_label.get());
        crot.PatchRgbArgs(0x461069, CosmeticState.rb_label.get());
    }
    if (s) {
        crot.PatchRgbArgs(0x460A6E, CosmeticState.rb_speed.get());
    }
}

fn HandleColorSettings(gf: *GlobalFn) callconv(.C) void {
    CosmeticState.rb_enable = gf.SettingGetB("cosmetic", "rainbow_enable").?;

    CosmeticState.rb_value_enable = gf.SettingGetB("cosmetic", "rainbow_value_enable").?;
    if (!CosmeticState.rb_enable or !CosmeticState.rb_value_enable) {
        crot.PatchRgbArgs(0x460E5D, 0xFFFFFF); // in-race hud UI numbers
        crot.PatchRgbArgs(0x460FB1, 0xFFFFFF);
        crot.PatchRgbArgs(0x461045, 0xFFFFFF);
    }

    CosmeticState.rb_label_enable = gf.SettingGetB("cosmetic", "rainbow_label_enable").?;
    if (!CosmeticState.rb_enable or !CosmeticState.rb_label_enable) {
        crot.PatchRgbArgs(0x460E8D, 0xFFFFFF); // in-race hud UI labels
        crot.PatchRgbArgs(0x460FE3, 0xFFFFFF);
        crot.PatchRgbArgs(0x461069, 0xFFFFFF);
    }

    CosmeticState.rb_speed_enable = gf.SettingGetB("cosmetic", "rainbow_speed_enable").?;
    if (!CosmeticState.rb_enable or !CosmeticState.rb_speed_enable) {
        crot.PatchRgbArgs(0x460A6E, 0x00C3FE); // in-race speedo number
    }
}

// SWE1R-PATCHER STUFF

fn PatchTextureTable(memory: usize, table_offset: usize, code_begin_offset: usize, code_end_offset: usize, width: u32, height: u32, filename: []const u8) usize {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var off: usize = memory;
    off = x86.nop_align(off, 16);

    // Original code takes u8 dimension args, so we use our own code that takes u32
    const cave_memory_offset: usize = off;

    // Patches the arguments for the texture loader
    off = x86.push_u32(off, height);
    off = x86.push_u32(off, width);
    off = x86.push_u32(off, height);
    off = x86.push_u32(off, width);
    off = x86.jmp(off, code_end_offset);

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
        const texture_new: usize = off;
        off = mem.write_bytes(off, &buffer[0], texture_size);

        // Patch the table entry
        //const texture_old: usize = mem.read(table_offset + 4 + i * 4, u32);
        _ = mem.write(table_offset + 4 + i * 4, u32, texture_new);
        //printf("%d: 0x%X -> 0x%X\n", i, texture_old, texture_new);
    }

    return off;
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
fn PatchSpriteLoaderToLoadTga(memory: usize) usize {
    // Replace the sprite loader with a version that checks for "data\\images\\sprite-%d.tga"
    var off: usize = memory;

    // Write the path we want to use to the binary
    const tga_path = "data\\sprites\\sprite-%d.tga";

    const offset_tga_path: usize = off;
    off = mem.write(off, @TypeOf(tga_path.*), tga_path.*);

    // FIXME: load_success: Yay! Shift down size, to compensate for higher resolution
    const offset_load_success: usize = off;

    // TODO: figure out what this asm means and make macros
    // Shift the width and height of the sprite to the right
    off = mem.write(off, u8, 0x66);
    off = mem.write(off, u8, 0xC1);
    off = mem.write(off, u8, 0x68);
    off = mem.write(off, u8, 0);
    off = mem.write(off, u8, 1);

    off = mem.write(off, u8, 0x66);
    off = mem.write(off, u8, 0xC1);
    off = mem.write(off, u8, 0x68);
    off = mem.write(off, u8, 2);
    off = mem.write(off, u8, 2);

    off = mem.write(off, u8, 0x66);
    off = mem.write(off, u8, 0xC1);
    off = mem.write(off, u8, 0x68);
    off = mem.write(off, u8, 14);
    off = mem.write(off, u8, 2);

    // Get address of page and repeat steps
    off = mem.write(off, u8, 0x8B);
    off = mem.write(off, u8, 0x50);
    off = mem.write(off, u8, 16);

    off = mem.write(off, u8, 0x66);
    off = mem.write(off, u8, 0xC1);
    off = mem.write(off, u8, 0x6A);
    off = mem.write(off, u8, 0);
    off = mem.write(off, u8, 1);

    off = mem.write(off, u8, 0x66);
    off = mem.write(off, u8, 0xC1);
    off = mem.write(off, u8, 0x6A);
    off = mem.write(off, u8, 2);
    off = mem.write(off, u8, 2);

    // Get address of texture and repeat steps

    //0:  8b 50 10                mov    edx,DWORD PTR [eax+0x10]
    //3:  66 c1 6a 02 02          shr    WORD PTR [edx+0x2],0x2

    // finish: Clear stack and return
    const offset_finish: usize = off;
    off = x86.add_esp32(off, 0x4 + 0x400);
    off = x86.retn(off);

    // Start of actual code
    const offset_tga_loader_code: usize = off;

    // Read the sprite_index from stack
    //  -> mov     eax, [esp+4]
    off = mem.write(off, u8, 0x8B);
    off = mem.write(off, u8, 0x44);
    off = mem.write(off, u8, 0x24);
    off = mem.write(off, u8, 0x04);

    // Make room for sprintf buffer and keep the pointer in edx
    off = x86.add_esp32(off, @bitCast(@as(i32, -0x400)));
    off = x86.mov_edx_esp(off);

    // Generate the path, keep sprite_index on stack as we'll keep using it
    off = x86.push_eax(off); // (sprite_index)
    off = x86.push_u32(off, offset_tga_path); // (fmt)
    off = x86.push_edx(off); // (buffer)
    off = x86.call(off, 0x49EB80); // sprintf
    off = x86.pop_edx(off); // (buffer)
    off = x86.add_esp32(off, 0x4);

    // Attempt to load the TGA, then remove path from stack
    off = x86.push_edx(off); // (buffer)
    off = x86.call(off, 0x4114D0); // load_sprite_from_tga_and_add_loaded_sprite
    off = x86.add_esp32(off, 0x4);

    // Check if the load failed
    off = x86.test_eax_eax(off);
    off = x86.jnz(off, offset_load_success);

    // Load failed, so load the original sprite (sprite-index still on stack)
    off = x86.call(off, 0x446CA0); // load_sprite_internal

    off = x86.jmp(off, offset_finish);

    // Install it by jumping from 0x446FB0 (and we'll return directly)
    _ = x86.jmp(0x446FB0, offset_tga_loader_code);

    return off;
}

fn PatchTriggerDisplay(memory: usize) usize {
    var off = memory;

    // Display triggers
    const trigger_string = "Trigger %d activated";
    const trigger_string_display_duration: f32 = 3.0;

    var offset_trigger_string = off;
    off = mem.write(off, @TypeOf(trigger_string.*), trigger_string.*);

    var offset_trigger_code: u32 = off;

    // Read the trigger from stack
    off = mem.write(off, u8, 0x8B); // mov    eax, [esp+4]
    off = mem.write(off, u8, 0x44);
    off = mem.write(off, u8, 0x24);
    off = mem.write(off, u8, 0x04);

    // Get pointer to section 8
    off = mem.write(off, u8, 0x8B); // 8b 40 4c  ->  mov    eax,DWORD PTR [eax+0x4c]
    off = mem.write(off, u8, 0x40);
    off = mem.write(off, u8, 0x4C);

    // Read the section8.trigger_action field
    off = mem.write(off, u8, 0x0F); // 0f b7 40 24  ->  movzx    eax, WORD PTR [eax+0x24]
    off = mem.write(off, u8, 0xB7);
    off = mem.write(off, u8, 0x40);
    off = mem.write(off, u8, 0x24);

    // Make room for sprintf buffer and keep the pointer in edx
    off = x86.add_esp32(off, @bitCast(@as(i32, -0x400))); // add    esp, -400h
    off = x86.mov_edx_esp(off);

    // Generate the string we'll display
    off = x86.push_eax(off); // (trigger index)
    off = x86.push_u32(off, offset_trigger_string); // (fmt)
    off = x86.push_edx(off); // (buffer)
    off = x86.call(off, 0x49EB80); // sprintf
    off = x86.pop_edx(off); // (buffer)
    off = x86.add_esp32(off, 0x8);

    // Display a message
    off = x86.push_u32(off, @bitCast(trigger_string_display_duration));
    off = x86.push_edx(off); // (buffer)
    off = x86.call(off, 0x44FCE0);
    off = x86.add_esp32(off, 0x8);

    // Pop the string buffer off of the stack
    off = x86.add_esp32(off, 0x400);

    // Jump to the real function to run the trigger
    off = x86.jmp(off, 0x47CE60);

    // Install it by replacing the call destination (we'll jump to the real one)
    _ = x86.call(0x476E80, offset_trigger_code);

    return off;
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
    HandleColorSettings(gf);

    // TODO: convert to use global allocator once it is part of the GlobalFn interface;
    // then we can properly deinit it when the plugin unloads or the user setting changes
    var off = gs.patch_offset;
    if (gf.SettingGetB("cosmetic", "patch_fonts").?) {
        off = PatchTextureTable(off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
        off = PatchTextureTable(off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
        off = PatchTextureTable(off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
        off = PatchTextureTable(off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
        off = PatchTextureTable(off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
    }
    //if (gf.SettingGetB("cosmetic", "patch_audio").?) {
    //    const sample_rate: u32 = 22050 * 2;
    //    const bits_per_sample: u8 = 16;
    //    const stereo: bool = true;
    //    PatchAudioStreamQuality(sample_rate, bits_per_sample, stereo);
    //}
    //if (gf.SettingGetB("cosmetic", "patch_tga_loader").?) {
    //    off = PatchSpriteLoaderToLoadTga(off);
    //}
    if (gf.SettingGetB("cosmetic", "patch_trigger_display").?) {
        off = PatchTriggerDisplay(off);
    }
    gs.patch_offset = off;
}

export fn OnInitLate(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
    crot.PatchRgbArgs(0x460E5D, 0xFFFFFF); // in-race hud UI numbers
    crot.PatchRgbArgs(0x460FB1, 0xFFFFFF);
    crot.PatchRgbArgs(0x461045, 0xFFFFFF);
    crot.PatchRgbArgs(0x460E8D, 0xFFFFFF); // in-race hud UI labels
    crot.PatchRgbArgs(0x460FE3, 0xFFFFFF);
    crot.PatchRgbArgs(0x461069, 0xFFFFFF);
    crot.PatchRgbArgs(0x460A6E, 0x00C3FE); // in-race speedo number
}

// HOOKS

export fn OnSettingsLoad(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gs;
    HandleColorSettings(gf);
}

export fn TextRenderB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
    if (CosmeticState.rb_enable) {
        PatchHudColRotate(
            CosmeticState.rb_value_enable,
            CosmeticState.rb_label_enable,
            CosmeticState.rb_speed_enable,
        );
    }
}
