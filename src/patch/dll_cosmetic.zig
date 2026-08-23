const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const crot = @import("util/color.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;
const Setting = @import("core/ASettings.zig").ASettingSent;

const ra = @import("racer").Asset;
const rt = @import("racer").Text;
const rf = @import("racer").Font;
const r3 = @import("racer").@"3D";

const debug_panic = @import("util/debug/debug_panic.zig");
pub const panic = debug_panic.PanicFromContext("plugin_cosmetic", "annodue/plugin/plugin_cosmetic.pdb");

// FEATURES
// - Rotating rainbow colors for race UI elements: top values, top labels, speedo
// - (disabled) High-fidelity audio
// - (disabled) Load sprites from TGA
// - SETTINGS:
//   rainbow_enable         bool    toggle all rainbow features collectively
//   rainbow_value_enable   bool
//   rainbow_label_enable   bool
//   rainbow_speed_enable   bool
//   patch_audio            bool    ignored
//   patch_tga_loader       bool    ignored

// TODO: finish porting/fixing swe1r-patcher features
// TODO: ?? custom static color as an option for the rainbow stuff?
// TODO: ?? realtime-based color scrolling (rather than frame-based)
// TODO: ?? tighter rotation of colors, so they look like they're following each other
// TODO: convert all allocations to global allocator once part of GlobalFn
// TODO: all settings hot-reloadable
// TODO: convert trigger display to our notification system

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
    var s_rb_enable: bool = false;
    var s_rb_value_enable: bool = false;
    var s_rb_label_enable: bool = false;
    var s_rb_speed_enable: bool = false;
    var rb_value = crot.RotatingRGB.new(95, 255, 0);
    var rb_label = crot.RotatingRGB.new(95, 255, 1);
    var rb_speed = crot.RotatingRGB.new(95, 255, 2);
    var s_patch_tga_loader: bool = false;
    var s_patch_audio: bool = false;

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

// WARN: not tested, also should verify consistency with old patch
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
    off = x86.SHR(off, .eax, @as(i16, 0x0), .imm, 1); // shr  WORD PTR [eax+0x0], 1
    off = x86.SHR(off, .eax, @as(i16, 0x2), .imm, 2); // shr  WORD PTR [eax+0x2], 2
    off = x86.SHR(off, .eax, @as(i16, 0xE), .imm, 2); // shr  WORD PTR [eax+0xE], 2

    // Get address of page and repeat steps
    off = mem.write_bytes(off, &[3]u8{ 0x8B, 0x50, 0x10 }); // mov  edx, DWORD PTR [eax+0x10]
    off = x86.SHR(off, .edx, @as(i16, 0x0), .imm, 1); // shr  WORD PTR [edx+0x0], 1
    off = x86.SHR(off, .edx, @as(i16, 0x2), .imm, 2); // shr  WORD PTR [edx+0x2], 2

    // Get address of texture and repeat steps
    //0:  8b 50 10                mov    edx,DWORD PTR [eax+0x10]
    //3:  66 c1 6a 02 02          shr    WORD PTR [edx+0x2],0x2

    // finish: Clear stack and return
    const offset_finish: usize = off;
    off = x86.ADD(off, .esp, null, .imm, 0x4 + 0x400);
    off = x86.retn(off);

    // Start of actual code
    const offset_tga_loader_code: usize = off;

    // Read the sprite_index from stack
    off = mem.write_bytes(off, &[4]u8{ 0x8B, 0x44, 0x24, 0x04 }); // mov  eax, [esp+0x04]

    // Make room for sprintf buffer and keep the pointer in edx
    off = x86.ADD(off, .esp, null, .imm, -0x400);
    off = x86.mov_rm32_r32(off, .edx, .esp); // mov edx, esp

    // Generate the path, keep sprite_index on stack as we'll keep using it
    off = x86.push(off, .{ .r32 = .eax }); // (sprite_index)
    off = x86.push(off, .{ .imm32 = offset_tga_path }); // (fmt)
    off = x86.push(off, .{ .r32 = .edx }); // (buffer)
    off = x86.call(off, 0x49EB80); // sprintf
    off = x86.pop(off, .{ .r32 = .edx }); // (buffer)
    off = x86.ADD(off, .esp, null, .imm, 0x4);

    // Attempt to load the TGA, then remove path from stack
    off = x86.push(off, .{ .r32 = .edx }); // (buffer)
    off = x86.call(off, 0x4114D0); // load_sprite_from_tga_and_add_loaded_sprite
    off = x86.ADD(off, .esp, null, .imm, 0x4);

    // Check if the load failed
    off = x86.test_eax_eax(off);
    off = x86.JNZ(off, offset_load_success);

    // Load failed, so load the original sprite (sprite-index still on stack)
    off = x86.call(off, 0x446CA0); // load_sprite_internal

    off = x86.jmp_rel(off, offset_finish);

    // Install it by jumping from 0x446FB0 (and we'll return directly)
    _ = x86.jmp_rel(0x446FB0, offset_tga_loader_code);

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

export fn OnInit(gf: *GlobalFn) callconv(.C) void {
    CosmeticState.settingsInit(gf);

    // TODO: convert to use global allocator once it is part of the GlobalFn interface;
    // then we can properly deinit it when the plugin unloads or the user setting changes.
    // could also statically allocate space on the DLL and include them in the binary
    // at comptime, in the format racer expects them.
    //var off = gs.patch_offset;

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
}

// HOOKS

export fn TextRenderB(_: *GlobalFn) callconv(.C) void {
    if (CosmeticState.s_rb_enable) {
        CosmeticState.PatchHudColRotate(
            CosmeticState.s_rb_value_enable,
            CosmeticState.s_rb_label_enable,
            CosmeticState.s_rb_speed_enable,
        );
    }
}
