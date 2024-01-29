const std = @import("std");
const user32 = std.os.windows.user32;

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

const mp = @import("patch_multiplayer.zig");
const mem = @import("util/memory.zig");
const settings = @import("util/settings.zig");
const SettingsGroup = settings.SettingsGroup;
const SettingsManager = settings.SettingsManager;
const ini = @import("import/ini/ini.zig");

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

fn PtrMessage(alloc: std.mem.Allocator, ptr: usize, label: []const u8) void {
    var buf = std.fmt.allocPrintZ(alloc, "{s}: 0x{x}", .{ label, ptr }) catch unreachable;
    _ = MessageBoxA(null, buf, "patch.dll", MB_OK);
}

fn PatchDeathSpeed(min: f32, drop: f32) void {
    _ = mem.write(0x4C7BB8, f32, min);
    _ = mem.write(0x4C7BBC, f32, drop);
}

export fn Patch() void {
    const mem_alloc = MEM_COMMIT | MEM_RESERVE;
    const mem_protect = PAGE_EXECUTE_READWRITE;
    const memory = VirtualAlloc(null, patch_size, mem_alloc, mem_protect) catch unreachable;
    var off: usize = @intFromPtr(memory);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // settings

    var s = SettingsManager.init(alloc);
    defer s.deinit();

    var s_gen = SettingsGroup.init(alloc, "general");
    defer s_gen.deinit();
    s_gen.add("death_speed_mod_enable", bool, false);
    s_gen.add("death_speed_min", f32, 325);
    s_gen.add("death_speed_drop", f32, 140);
    s.add(&s_gen);

    var s_mp = SettingsGroup.init(alloc, "multiplayer");
    defer s_mp.deinit();
    s_mp.add("multiplayer_mod_enable", bool, false);
    s_mp.add("patch_netplay", bool, false);
    s_mp.add("netplay_guid", bool, false); // FIXME: crash on startup, all others don't
    s_mp.add("netplay_r100", bool, false);
    s_mp.add("patch_audio", bool, false);
    s_mp.add("patch_fonts", bool, false); // working
    s_mp.add("fonts_dump", bool, false); // working?
    s_mp.add("patch_tga_loader", bool, false);
    s_mp.add("patch_trigger_display", bool, false); // working
    s.add(&s_mp);

    s.read_ini(alloc, "annodue/settings.ini") catch unreachable;

    // random stuff

    if (s_gen.get("death_speed_mod_enable", bool)) {
        const dsm = s_gen.get("death_speed_min", f32);
        const dsd = s_gen.get("death_speed_drop", f32);
        PatchDeathSpeed(dsm, dsd);
    }

    // swe1r-patcher (multiplayer mod) stuff

    if (s_mp.get("multiplayer_mod_enable", bool)) {
        if (s_mp.get("fonts_dump", bool)) {
            // This is a debug feature to dump the original font textures
            _ = mp.DumpTextureTable(alloc, 0x4BF91C, 3, 0, 64, 128, "font0");
            _ = mp.DumpTextureTable(alloc, 0x4BF7E4, 3, 0, 64, 128, "font1");
            _ = mp.DumpTextureTable(alloc, 0x4BF84C, 3, 0, 64, 128, "font2");
            _ = mp.DumpTextureTable(alloc, 0x4BF8B4, 3, 0, 64, 128, "font3");
            _ = mp.DumpTextureTable(alloc, 0x4BF984, 3, 0, 64, 128, "font4");
        }
        if (s_mp.get("patch_fonts", bool)) {
            off = mp.PatchTextureTable(alloc, off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
            off = mp.PatchTextureTable(alloc, off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
            off = mp.PatchTextureTable(alloc, off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
            off = mp.PatchTextureTable(alloc, off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
            off = mp.PatchTextureTable(alloc, off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
        }
        if (s_mp.get("patch_netplay", bool)) {
            const r100 = s_mp.get("netplay_r100", bool);
            const guid = s_mp.get("netplay_guid", bool);
            const traction: u8 = if (r100) 3 else 5;
            var upgrade_lv: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
            var upgrade_hp: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
            const upgrade_lv_ptr: *[7]u8 = @ptrCast(&upgrade_lv);
            const upgrade_hp_ptr: *[7]u8 = @ptrCast(&upgrade_hp);
            off = mp.PatchNetworkUpgrades(off, upgrade_lv_ptr, upgrade_hp_ptr, guid);
            off = mp.PatchNetworkCollisions(off, guid);
        }
        if (s_mp.get("patch_audio", bool)) {
            const sample_rate: u32 = 22050 * 2;
            const bits_per_sample: u8 = 16;
            const stereo: bool = true;
            off = mp.PatchAudioStreamQuality(off, sample_rate, bits_per_sample, stereo);
        }
        if (s_mp.get("patch_tga_loader", bool)) {
            off = mp.PatchSpriteLoaderToLoadTga(off);
        }
        if (s_mp.get("patch_trigger_display", bool)) {
            off = mp.PatchTriggerDisplay(off);
        }
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
