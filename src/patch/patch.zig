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
const set = @import("util/settings.zig");
const SettingsGroup = set.SettingsGroup;
const SettingsManager = set.SettingsManager;
const ini = @import("import/ini/ini.zig");

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

const s = struct {
    var manager: SettingsManager = undefined;
    var gen: SettingsGroup = undefined;
    var mp: SettingsGroup = undefined;
};

fn PtrMessage(alloc: std.mem.Allocator, ptr: usize, label: []const u8) void {
    var buf = std.fmt.allocPrintZ(alloc, "{s}: 0x{x}", .{ label, ptr }) catch unreachable;
    _ = MessageBoxA(null, buf, "patch.dll", MB_OK);
}

fn PatchDeathSpeed(min: f32, drop: f32) void {
    _ = mem.write(0x4C7BB8, f32, min);
    _ = mem.write(0x4C7BBC, f32, drop);
}

fn PatchHudTimerColRotate() void { // 0xFFFFFFBE
    const col = struct {
        const min: u8 = 63;
        const max: u8 = 255;
        var rgb: [3]u8 = .{ 255, 63, 63 };
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

fn GameLoopAfter() void {
    if (s.gen.get("rainbow_timer_enable", bool)) {
        PatchHudTimerColRotate();
    }
}

fn HookGameLoop(memory: usize) usize {
    const off_this: usize = 0x49CE2A;
    const off_next: usize = 0x49CE2F;
    var offset: usize = memory;

    const call_old: i32 = mem.read(off_this + 1, i32);
    const off_gameloop: usize = @bitCast(@as(i32, @bitCast(off_next)) + call_old);

    // redirect to our code
    _ = mem.call(0x49CE2A, offset);

    // call the game loop manually, do our thing, then send it back
    offset = mem.call(offset, off_gameloop);
    offset = mem.call(offset, @intFromPtr(&GameLoopAfter));
    offset = mem.retn(offset);
    offset = mem.nop_align(offset, 16);

    return offset;
}

export fn Patch() void {
    const mem_alloc = MEM_COMMIT | MEM_RESERVE;
    const mem_protect = PAGE_EXECUTE_READWRITE;
    const memory = VirtualAlloc(null, patch_size, mem_alloc, mem_protect) catch unreachable;
    var off: usize = @intFromPtr(memory);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // settings

    // FIXME: i guess we have to not deinit anything for now,
    // since they need to be available in the game loop?
    // one other strategy might be to set globals for stuff
    // we need to keep, and go back to deinit-ing. then we also
    // wouldn't have to do hash lookups constantly too.

    s.manager = SettingsManager.init(alloc);
    //defer s.deinit();

    s.gen = SettingsGroup.init(alloc, "general");
    //defer s_gen.deinit();
    s.gen.add("death_speed_mod_enable", bool, false);
    s.gen.add("death_speed_min", f32, 325);
    s.gen.add("death_speed_drop", f32, 140);
    s.gen.add("rainbow_timer_enable", bool, false);
    s.manager.add(&s.gen);

    s.mp = SettingsGroup.init(alloc, "multiplayer");
    //defer s_mp.deinit();
    s.mp.add("multiplayer_mod_enable", bool, false);
    s.mp.add("patch_netplay", bool, false);
    s.mp.add("netplay_guid", bool, false); // FIXME: crash on startup, all others don't
    s.mp.add("netplay_r100", bool, false);
    s.mp.add("patch_audio", bool, false);
    s.mp.add("patch_fonts", bool, false); // working
    s.mp.add("fonts_dump", bool, false); // working?
    s.mp.add("patch_tga_loader", bool, false);
    s.mp.add("patch_trigger_display", bool, false); // working
    s.manager.add(&s.mp);

    s.manager.read_ini(alloc, "annodue/settings.ini") catch unreachable;

    // random stuff

    off = HookGameLoop(off);

    if (s.gen.get("death_speed_mod_enable", bool)) {
        const dsm = s.gen.get("death_speed_min", f32);
        const dsd = s.gen.get("death_speed_drop", f32);
        PatchDeathSpeed(dsm, dsd);
    }

    // swe1r-patcher (multiplayer mod) stuff

    if (s.mp.get("multiplayer_mod_enable", bool)) {
        if (s.mp.get("fonts_dump", bool)) {
            // This is a debug feature to dump the original font textures
            _ = mp.DumpTextureTable(alloc, 0x4BF91C, 3, 0, 64, 128, "font0");
            _ = mp.DumpTextureTable(alloc, 0x4BF7E4, 3, 0, 64, 128, "font1");
            _ = mp.DumpTextureTable(alloc, 0x4BF84C, 3, 0, 64, 128, "font2");
            _ = mp.DumpTextureTable(alloc, 0x4BF8B4, 3, 0, 64, 128, "font3");
            _ = mp.DumpTextureTable(alloc, 0x4BF984, 3, 0, 64, 128, "font4");
        }
        if (s.mp.get("patch_fonts", bool)) {
            off = mp.PatchTextureTable(alloc, off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
            off = mp.PatchTextureTable(alloc, off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
            off = mp.PatchTextureTable(alloc, off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
            off = mp.PatchTextureTable(alloc, off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
            off = mp.PatchTextureTable(alloc, off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
        }
        if (s.mp.get("patch_netplay", bool)) {
            const r100 = s.mp.get("netplay_r100", bool);
            const guid = s.mp.get("netplay_guid", bool);
            const traction: u8 = if (r100) 3 else 5;
            var upgrade_lv: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
            var upgrade_hp: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
            const upgrade_lv_ptr: *[7]u8 = @ptrCast(&upgrade_lv);
            const upgrade_hp_ptr: *[7]u8 = @ptrCast(&upgrade_hp);
            off = mp.PatchNetworkUpgrades(off, upgrade_lv_ptr, upgrade_hp_ptr, guid);
            off = mp.PatchNetworkCollisions(off, guid);
        }
        if (s.mp.get("patch_audio", bool)) {
            const sample_rate: u32 = 22050 * 2;
            const bits_per_sample: u8 = 16;
            const stereo: bool = true;
            off = mp.PatchAudioStreamQuality(off, sample_rate, bits_per_sample, stereo);
        }
        if (s.mp.get("patch_tga_loader", bool)) {
            off = mp.PatchSpriteLoaderToLoadTga(off);
        }
        if (s.mp.get("patch_trigger_display", bool)) {
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
