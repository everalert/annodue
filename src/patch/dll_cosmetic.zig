const Self = @This();

const std = @import("std");

const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const crot = @import("util/color.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;
const Setting = @import("core/ASettings.zig").ASettingSent;

const ra = @import("racer").Asset;
const rt = @import("racer").Text;
const rf = @import("racer").Font;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// - High-resolution fonts
// - Rotating rainbow colors for race UI elements: top values, top labels, speedo
// - (disabled) High-fidelity audio
// - (disabled) Load sprites from TGA
// - SETTINGS:
//   rainbow_enable         bool    toggle all rainbow features collectively
//   rainbow_value_enable   bool
//   rainbow_label_enable   bool
//   rainbow_speed_enable   bool
//   patch_fonts            bool    * requires game restart to apply
//   patch_audio            bool    ignored
//   patch_tga_loader       bool    ignored

// TODO: finish porting/fixing swe1r-patcher features
// TODO: ?? custom static color as an option for the rainbow stuff?
// TODO: ?? realtime-based color scrolling (rather than frame-based)
// TODO: ?? tighter rotation of colors, so they look like they're following each other
// TODO: convert all allocations to global allocator once part of GlobalFn
// TODO: all settings hot-reloadable
// TODO: convert trigger display to our notification system
// TODO: embed fonts and point to ours, rather than patching the whole thing (for faster loadtimes)

const PLUGIN_NAME: [*:0]const u8 = "Cosmetic";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const CosmeticState = struct {
    var h_s_section: ?SettingHandle = null;
    var h_s_rb_enable: ?SettingHandle = null;
    var h_s_rb_value_enable: ?SettingHandle = null;
    var h_s_rb_label_enable: ?SettingHandle = null;
    var h_s_rb_speed_enable: ?SettingHandle = null;
    var h_s_patch_tga_loader: ?SettingHandle = null;
    var h_s_patch_audio: ?SettingHandle = null;
    var h_s_patch_fonts: ?SettingHandle = null;
    var s_rb_enable: bool = false;
    var s_rb_value_enable: bool = false;
    var s_rb_label_enable: bool = false;
    var s_rb_speed_enable: bool = false;
    var rb_value = crot.RotatingRGB.new(95, 255, 0);
    var rb_label = crot.RotatingRGB.new(95, 255, 1);
    var rb_speed = crot.RotatingRGB.new(95, 255, 2);
    var s_patch_tga_loader: bool = false;
    var s_patch_audio: bool = false;
    var s_patch_fonts: bool = false;

    // FIXME: sized specifically for original font patch, will need to be changed for future
    // FIXME: doing it this way (without annodue alloc) also causes the game to crash whenever
    // the dll unloads, which for now is fine just to get rid of global state ref, because
    // reworking the font patch is high priority anyway
    var font_buf: [0x1D0000]u8 = undefined;

    fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "cosmetic", settingsUpdate);
        h_s_section = section;

        h_s_rb_enable =
            gf.ASettingOccupy(section, "rainbow_enable", .B, .{ .b = false }, &s_rb_enable, null);
        h_s_rb_value_enable =
            gf.ASettingOccupy(section, "rainbow_value_enable", .B, .{ .b = false }, &s_rb_value_enable, null);
        h_s_rb_label_enable =
            gf.ASettingOccupy(section, "rainbow_label_enable", .B, .{ .b = false }, &s_rb_label_enable, null);
        h_s_rb_speed_enable =
            gf.ASettingOccupy(section, "rainbow_speed_enable", .B, .{ .b = false }, &s_rb_speed_enable, null);

        h_s_patch_tga_loader = // FIXME: need tga files to verify with
            gf.ASettingOccupy(section, "patch_tga_loader", .B, .{ .b = false }, &s_patch_tga_loader, null);
        h_s_patch_audio = // FIXME: crashes
            gf.ASettingOccupy(section, "patch_audio", .B, .{ .b = false }, &s_patch_audio, null);
        h_s_patch_fonts =
            gf.ASettingOccupy(section, "patch_fonts", .B, .{ .b = false }, &s_patch_fonts, null);
    }

    fn settingsUpdate(changed: [*]Setting, len: usize) callconv(.C) void {
        var update_rb_value: bool = false;
        var update_rb_label: bool = false;
        var update_rb_speed: bool = false;

        for (changed, 0..len) |setting, _| {
            const nlen: usize = std.mem.len(setting.name);

            if (nlen == 14 and std.mem.eql(u8, "rainbow_enable", setting.name[0..nlen])) {
                update_rb_value = true;
                update_rb_label = true;
                update_rb_speed = true;
                continue;
            }
            if (nlen == 20 and std.mem.eql(u8, "rainbow_value_enable", setting.name[0..nlen])) {
                update_rb_value = true;
                continue;
            }
            if (nlen == 20 and std.mem.eql(u8, "rainbow_label_enable", setting.name[0..nlen])) {
                update_rb_label = true;
                continue;
            }
            if (nlen == 20 and std.mem.eql(u8, "rainbow_speed_enable", setting.name[0..nlen])) {
                update_rb_speed = true;
                continue;
            }
        }

        if (update_rb_value and (!s_rb_enable or !s_rb_value_enable)) {
            crot.PatchRgbArgs(0x460E5D, 0xFFFFFF); // in-race hud UI numbers
            crot.PatchRgbArgs(0x460FB1, 0xFFFFFF);
            crot.PatchRgbArgs(0x461045, 0xFFFFFF);
        }

        if (update_rb_label and (!s_rb_enable or !s_rb_label_enable)) {
            crot.PatchRgbArgs(0x460E8D, 0xFFFFFF); // in-race hud UI labels
            crot.PatchRgbArgs(0x460FE3, 0xFFFFFF);
            crot.PatchRgbArgs(0x461069, 0xFFFFFF);
        }

        if (update_rb_speed and (!s_rb_enable or !s_rb_speed_enable)) {
            crot.PatchRgbArgs(0x460A6E, 0x00C3FE); // in-race speedo number
        }
    }

    // COLOR CHANGES

    fn PatchHudColRotate(value: bool, label: bool, speed: bool) void {
        rb_value.update();
        rb_label.update();
        rb_speed.update();
        if (value) {
            crot.PatchRgbArgs(0x460E5D, rb_value.get());
            crot.PatchRgbArgs(0x460FB1, rb_value.get());
            crot.PatchRgbArgs(0x461045, rb_value.get());
        }
        if (label) {
            crot.PatchRgbArgs(0x460E8D, rb_label.get());
            crot.PatchRgbArgs(0x460FE3, rb_label.get());
            crot.PatchRgbArgs(0x461069, rb_label.get());
        }
        if (speed) {
            crot.PatchRgbArgs(0x460A6E, rb_speed.get());
        }
    }
};

// SWE1R-PATCHER STUFF

// NOTE: the original patcher referred to this as a 'texture' table, but this is
// actually a vtable pointing to 'sprite'-type pages; this is the same basic format
// as other sprites, but all of the header data is stripped in the case of the
// embedded font data, in lieu of hardcoded assumptions about format, dimensions, etc.
// WARNING: the original dumped font data (see dll_developer) has some offset pixels
// and wrapping, but the hd fonts don't; not sure if this is handled by this function
// or if the dumper is just dumping wrong
// WARNING: also don't really know how the '.data' files this function takes were
// generated from the png files
// ---- comments from when originally porting below ----
// NOTE: code_begin_offset = part of the arguments to a function call (sprite
// setup-related fn fn_445EE0); args expected in this range: maxwidth?, maxheight?,
// width, height (args 3-6)
// NOTE: code_end_offset = the instruction after 4 arguments later
// NOTE: texture table seems to be 'len' in first field (u32), followed by len ptrs
// to texture segments
// FIXME: can probably convert font->sprite conversion to comptime embed then hook
// up ptrs only in code, then all the allocation bs can be skipped
// NOTE: probably cannot reverse this, because it patches something that seems to
// only run once during setup
fn PatchTextureTable(
    memory: usize,
    table_offset: usize,
    code_begin_offset: usize,
    code_end_offset: usize,
    width: u32,
    height: u32,
    filename: []const u8,
) usize {
    var off: usize = memory;
    off = x86.nop_align(off, 16);

    // Original code takes u8 dimension args, so we use our own code that takes u32
    const cave_memory_offset: usize = off;

    // Patches the arguments for the texture loader
    off = x86.push(off, .{ .imm32 = height });
    off = x86.push(off, .{ .imm32 = width });
    off = x86.push(off, .{ .imm32 = height });
    off = x86.push(off, .{ .imm32 = width });
    off = x86.jmp(off, code_end_offset);

    // Detour original code to ours
    var hack_offset: usize = x86.jmp(code_begin_offset, cave_memory_offset);
    _ = x86.nop_until(hack_offset, code_end_offset);

    const page_num: u32 = mem.read(table_offset + 0, u32);

    for (0..page_num) |i| {
        _ = mem.write(table_offset + 4 + i * 4, u32, off); // update table entry ptr
        off = LoadSpritePage(off, width, height, filename, i);
    }

    return off;
}

// loads some GIMP format into Greyscale4 format (0x400) in preparation for game
// parsing as sprite data
fn LoadSpritePage(
    write_at: u32,
    width: u32,
    height: u32,
    filename: []const u8,
    page: u32,
) u32 {
    var off = write_at;

    const page_size: u32 = width * height * 4 / 8;

    // Loop over all pages
    var str_buf: [1023:0]u8 = undefined;
    const buffer_slice = @as([*]u8, @ptrFromInt(off))[0..page_size];
    @memset(buffer_slice, 0x00);

    // Load input texture to buffer
    var path = std.fmt.bufPrintZ(&str_buf, "annodue/textures/{s}_{d}_test.data", .{ filename, page }) catch
        @panic("failed to format path for texture table patch"); // FIXME: error handling

    const file = std.fs.cwd().openFile(path, .{}) catch
        @panic("failed to open texture table patch file"); // FIXME: error handling
    defer file.close();
    var j: u32 = 0;
    while (j < page_size * 2) : (j += 1) {
        var pixel: [2]u8 = undefined; // GIMP only exports Gray + Alpha..
        _ = file.read(&pixel) catch
            @panic("failed to read segment of texture table patch file"); // FIXME: error handling
        buffer_slice[j / 2] |= (pixel[0] & 0xF0) >> @as(u3, @truncate((j % 2) * 4));
    }

    off += page_size;
    off = x86.nop_align(off, 0x10);
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
    off = x86.push(off, .{ .r32 = .eax }); // (sprite_index)
    off = x86.push(off, .{ .imm32 = offset_tga_path }); // (fmt)
    off = x86.push(off, .{ .r32 = .edx }); // (buffer)
    off = x86.call(off, 0x49EB80); // sprintf
    off = x86.pop(off, .{ .r32 = .edx }); // (buffer)
    off = x86.add_esp32(off, 0x4);

    // Attempt to load the TGA, then remove path from stack
    off = x86.push(off, .{ .r32 = .edx }); // (buffer)
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

// FIXME: move
const font_table = [_]*anyopaque{ &fonts[3], &fonts[2], &fonts[1], &fonts[2], &fonts[4], &fonts[3], &fonts[0] };
var fonts: [5]rf.FONT = undefined;
var fonts_loaded: bool = false;
var dp: ?*i32 = null;
var fonts_using: bool = false;

export fn OnInit(gf: *GlobalFn) callconv(.C) void {
    CosmeticState.settingsInit(gf);

    // TODO: convert to use global allocator once it is part of the GlobalFn interface;
    // then we can properly deinit it when the plugin unloads or the user setting changes.
    // could also statically allocate space on the DLL and include them in the binary
    // at comptime, in the format racer expects them.
    // NOTE: original function at fn_42D720
    //var off = gs.patch_offset;
    if (CosmeticState.s_patch_fonts) {
        var off = @intFromPtr(&CosmeticState.font_buf);
        // old
        //off = PatchTextureTable(off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
        //off = PatchTextureTable(off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
        //off = PatchTextureTable(off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
        //off = PatchTextureTable(off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
        //off = PatchTextureTable(off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
        // new
        @memcpy(&fonts, rf.aFontDef);
        fonts[0]._08_page_list[0] = @ptrFromInt(off);
        off = LoadSpritePage(off, 512, 1024, "font1", 0);
        ra.Material_CreateFromSpritePage(3, 0, 512, 1024, 512, 1024, @ptrCast(&fonts[0]._08_page_list[0]), &dp, 1, 0);
        fonts[0]._08_page_list[1] = @ptrFromInt(off);
        off = LoadSpritePage(off, 512, 1024, "font1", 1);
        ra.Material_CreateFromSpritePage(3, 0, 512, 1024, 512, 1024, @ptrCast(&fonts[0]._08_page_list[1]), &dp, 1, 0);
        fonts[0]._08_page_list[2] = @ptrFromInt(off);
        off = LoadSpritePage(off, 512, 1024, "font1", 2);
        ra.Material_CreateFromSpritePage(3, 0, 512, 1024, 512, 1024, @ptrCast(&fonts[0]._08_page_list[2]), &dp, 1, 0);
        fonts[1]._08_page_list[0] = @ptrFromInt(off);
        off = LoadSpritePage(off, 512, 1024, "font2", 0);
        ra.Material_CreateFromSpritePage(3, 0, 512, 1024, 512, 1024, @ptrCast(&fonts[1]._08_page_list[0]), &dp, 1, 0);
        fonts[2]._08_page_list[0] = @ptrFromInt(off);
        off = LoadSpritePage(off, 512, 1024, "font3", 0);
        ra.Material_CreateFromSpritePage(3, 0, 512, 1024, 512, 1024, @ptrCast(&fonts[2]._08_page_list[0]), &dp, 1, 0);
        fonts[3]._08_page_list[0] = @ptrFromInt(off);
        off = LoadSpritePage(off, 512, 1024, "font0", 0);
        ra.Material_CreateFromSpritePage(3, 0, 512, 1024, 512, 1024, @ptrCast(&fonts[3]._08_page_list[0]), &dp, 1, 0);
        fonts[4]._08_page_list[0] = @ptrFromInt(off);
        off = LoadSpritePage(off, 512, 1024, "font4", 0);
        ra.Material_CreateFromSpritePage(3, 0, 512, 1024, 512, 1024, @ptrCast(&fonts[4]._08_page_list[0]), &dp, 1, 0);
        fonts_loaded = true;
        // yep
        std.debug.assert(off - @intFromPtr(&CosmeticState.font_buf) <= CosmeticState.font_buf.len);
    }
    //if (CosmeticState.s_patch_audio) {
    //    const sample_rate: u32 = 22050 * 2;
    //    const bits_per_sample: u8 = 16;
    //    const stereo: bool = true;
    //    PatchAudioStreamQuality(sample_rate, bits_per_sample, stereo);
    //}
    //if (CosmeticState.s_patch_tga_loader) {
    //    off = PatchSpriteLoaderToLoadTga(off);
    //}
    //gs.patch_offset = off;
}

export fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalFn) callconv(.C) void {
    crot.PatchRgbArgs(0x460E5D, 0xFFFFFF); // in-race hud UI numbers
    crot.PatchRgbArgs(0x460FB1, 0xFFFFFF);
    crot.PatchRgbArgs(0x461045, 0xFFFFFF);
    crot.PatchRgbArgs(0x460E8D, 0xFFFFFF); // in-race hud UI labels
    crot.PatchRgbArgs(0x460FE3, 0xFFFFFF);
    crot.PatchRgbArgs(0x461069, 0xFFFFFF);
    crot.PatchRgbArgs(0x460A6E, 0x00C3FE); // in-race speedo number

    if (fonts_loaded) {
        _ = mem.write(0x42D8EE + 3, u32, 0xE99720);
        ra.Material_Free(@ptrCast(&fonts[0]._08_page_list[0]));
        ra.Material_Free(@ptrCast(&fonts[1]._08_page_list[0]));
        ra.Material_Free(@ptrCast(&fonts[1]._08_page_list[1]));
        ra.Material_Free(@ptrCast(&fonts[1]._08_page_list[2]));
        ra.Material_Free(@ptrCast(&fonts[2]._08_page_list[0]));
        ra.Material_Free(@ptrCast(&fonts[3]._08_page_list[0]));
        ra.Material_Free(@ptrCast(&fonts[4]._08_page_list[0]));
        fonts_loaded = false;
    }
}

// HOOKS

export fn TextRenderB(gf: *GlobalFn) callconv(.C) void {
    if (fonts_loaded and gf.InputGetKbRaw(.K) == .JustOn) {
        if (fonts_using) {
            fonts_using = false;
            _ = mem.write(0x42D8EE + 3, u32, @intFromPtr(rt.apTextFont));
        } else {
            fonts_using = true;
            _ = mem.write(0x42D8EE + 3, u32, @intFromPtr(&font_table));
            //const SetCurrentFontSource: *align(1) *anyopaque = @ptrFromInt(0x42D8EE + 3);
            //SetCurrentFontSource.* = @constCast(@ptrCast(&font_table));
        }
    }

    if (CosmeticState.s_rb_enable) {
        CosmeticState.PatchHudColRotate(
            CosmeticState.s_rb_value_enable,
            CosmeticState.s_rb_label_enable,
            CosmeticState.s_rb_speed_enable,
        );
    }
}
