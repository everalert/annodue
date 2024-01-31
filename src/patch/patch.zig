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
const gen = @import("patch_general.zig");
const mem = @import("util/memory.zig");
const SettingsGroup = @import("util/settings.zig").SettingsGroup;
const SettingsManager = @import("util/settings.zig").SettingsManager;
const ini = @import("import/ini/ini.zig");

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

const s = struct { // FIXME: yucky
    var manager: SettingsManager = undefined;
    var gen: SettingsGroup = undefined;
    var mp: SettingsGroup = undefined;
};

fn PtrMessage(alloc: std.mem.Allocator, ptr: usize, label: []const u8) void {
    var buf = std.fmt.allocPrintZ(alloc, "{s}: 0x{x}", .{ label, ptr }) catch unreachable;
    _ = MessageBoxA(null, buf, "annodue.dll", MB_OK);
}

fn GameLoopAfter() void {
    if (s.gen.get("rainbow_timer_enable", bool)) {
        gen.PatchHudTimerColRotate();
    }
}

fn HookGameLoop(memory: usize) usize {
    const off_this: usize = 0x49CE2A;
    const off_next: usize = 0x49CE2F;
    var offset: usize = memory;

    const call_old: i32 = mem.read(off_this + 1, i32);
    const off_gameloop: usize = @bitCast(@as(i32, @bitCast(off_next)) + call_old);

    _ = mem.call(0x49CE2A, offset);

    offset = mem.call(offset, off_gameloop);
    offset = mem.call(offset, @intFromPtr(&GameLoopAfter));
    offset = mem.retn(offset);
    offset = mem.nop_align(offset, 16);

    return offset;
}

fn GameEnd() void {
    defer s.manager.deinit();
    defer s.gen.deinit();
    defer s.mp.deinit();
}

fn HookGameEnd(memory: usize) usize {
    const exit1_off: usize = 0x49CE31;
    const exit2_off: usize = 0x49CE3D;
    const exit1_len: usize = exit2_off - exit1_off - 1; // excluding retn
    const exit2_len: usize = 0x49CE48 - exit2_off - 1; // excluding retn
    var offset: usize = memory;

    offset = mem.detour(offset, exit1_off, exit1_len, &GameEnd);
    offset = mem.detour(offset, exit2_off, exit2_len, &GameEnd);

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

    // FIXME: deinits happen in GameEnd, see HookGameEnd.
    // probably not necessary to deinit at all tho.
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
    s.gen.add("ms_timer_enable", bool, false);
    s.manager.add(&s.gen);

    s.mp = SettingsGroup.init(alloc, "multiplayer");
    //defer s_mp.deinit();
    s.mp.add("multiplayer_mod_enable", bool, false); // working?
    s.mp.add("patch_netplay", bool, false); // working? ups ok, coll ?
    s.mp.add("netplay_guid", bool, false); // working?
    s.mp.add("netplay_r100", bool, false); // working
    s.mp.add("patch_audio", bool, false);
    s.mp.add("patch_fonts", bool, false); // working
    s.mp.add("fonts_dump", bool, false); // working?
    s.mp.add("patch_tga_loader", bool, false);
    s.mp.add("patch_trigger_display", bool, false); // working
    s.manager.add(&s.mp);

    s.manager.read_ini(alloc, "annodue/settings.ini") catch unreachable;

    // random stuff

    off = HookGameLoop(off);
    off = HookGameEnd(off);

    if (s.gen.get("death_speed_mod_enable", bool)) {
        const dsm = s.gen.get("death_speed_min", f32);
        const dsd = s.gen.get("death_speed_drop", f32);
        gen.PatchDeathSpeed(dsm, dsd);
    }
    if (s.gen.get("ms_timer_enable", bool)) {
        gen.PatchHudTimerMs();
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
            mp.PatchAudioStreamQuality(sample_rate, bits_per_sample, stereo);
        }
        if (s.mp.get("patch_tga_loader", bool)) {
            off = mp.PatchSpriteLoaderToLoadTga(off);
        }
        if (s.mp.get("patch_trigger_display", bool)) {
            off = mp.PatchTriggerDisplay(off);
        }
    }

    // debug

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
