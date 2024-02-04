const std = @import("std");
const user32 = std.os.windows.user32;

const VirtualAlloc = std.os.windows.VirtualAlloc;
const VirtualFree = std.os.windows.VirtualFree;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const MEM_RELEASE = std.os.windows.MEM_RELEASE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;
const WINAPI = std.os.windows.WINAPI;

const MessageBoxA = user32.MessageBoxA;
const MB_OK = user32.MB_OK;
const MB_ICONINFORMATION = user32.MB_ICONINFORMATION;

const win = @import("util/windows.zig");

const mp = @import("patch_multiplayer.zig");
const gen = @import("patch_general.zig");
const practice = @import("patch_practice.zig");

const mem = @import("util/memory.zig");

const rc = @import("util/racer_const.zig");
const UpgradeNames = rc.UpgradeNames;
const UpgradeCategories = rc.UpgradeCategories;
const ADDR_IN_RACE = rc.ADDR_IN_RACE;
const ADDR_DRAW_MENU_JUMP_TABLE = rc.ADDR_DRAW_MENU_JUMP_TABLE;

const swrText_CreateEntry1 = @import("util/racer_fn.zig").swrText_CreateEntry1;

const SettingsGroup = @import("util/settings.zig").SettingsGroup;
const SettingsManager = @import("util/settings.zig").SettingsManager;
const ini = @import("import/ini/ini.zig");

const ver_major: u32 = 0;
const ver_minor: u32 = 0;
const ver_patch: u32 = 1;

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

const s = struct { // FIXME: yucky
    var manager: SettingsManager = undefined;
    var gen: SettingsGroup = undefined;
    var prac: SettingsGroup = undefined;
    var mp: SettingsGroup = undefined;
};

const global = struct {
    var practice_mode: bool = false;
};

fn PtrMessage(ptr: usize, label: []const u8) void {
    var buf: [255:0]u8 = undefined;
    buf = std.fmt.bufPrintZ("{s}: 0x{s}", .{ label, ptr }) catch return;
    _ = MessageBoxA(null, buf, "annodue.dll", MB_OK);
}

fn ErrMessage(label: []const u8, err: []const u8) void {
    var buf: [2047:0]u8 = undefined;
    buf = std.fmt.bufPrintZ("[ERROR] {s}: {s}", .{ label, err }) catch return;
    _ = MessageBoxA(null, buf, "annodue.dll", MB_OK);
}

// GAME LOOP

fn GameLoop_Before() void {
    const state = struct {
        var initialized: bool = false;
    };

    if (!state.initialized) {
        const def_laps: u32 = s.gen.get("default_laps", u32);
        if (def_laps >= 1 and def_laps <= 5) {
            const laps: usize = mem.deref(&.{ 0x4BFDB8, 0x8F });
            _ = mem.write(laps, u8, @as(u8, @truncate(def_laps)));
        }
        const def_racers: u32 = s.gen.get("default_racers", u32);
        if (def_racers >= 1 and def_racers <= 12) {
            const addr_racers: usize = 0x50C558;
            _ = mem.write(addr_racers, u8, @as(u8, @truncate(def_racers)));
        }

        state.initialized = true;
    }

    if (s.gen.get("rainbow_timer_enable", bool)) {
        gen.PatchHudTimerColRotate();
    }
}

fn GameLoop_After() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0GameLoop_After");
}

fn HookGameLoop(memory: usize) usize {
    return mem.intercept_call(memory, 0x49CE2A, &GameLoop_Before, &GameLoop_After);
}

// GAME END; executable closing

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

    offset = mem.detour(offset, exit1_off, exit1_len, null, &GameEnd);
    offset = mem.detour(offset, exit2_off, exit2_len, null, &GameEnd);

    return offset;
}

// MENU DRAW CALLS in 'Hang' callback0x14

fn MenuTitleScreen_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuTitleScreen_Before");
}

fn MenuVehicleSelect_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuVehicleSelect_Before");
}

fn MenuStartRace_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuStartRace_Before");
}

fn MenuJunkyard_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuJunkyard_Before");
}

fn MenuRaceResults_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuRaceResults_Before");
}

fn MenuWattosShop_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuWattosShop_Before");
}

fn MenuHangar_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuHangar_Before");
}

fn MenuTrackSelect_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuTrackSelect_Before");
}

fn MenuTrack_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuTrack_Before");
}

fn MenuCantinaEntry_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuCantinaEntry_Before");
}

fn HookMenuDrawing(memory: usize) usize {
    var off: usize = memory;

    // before 0x435240
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 1, &MenuTitleScreen_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 3, &MenuStartRace_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 4, &MenuJunkyard_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 5, &MenuRaceResults_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 7, &MenuWattosShop_Before);
    // before 0x______; inspect vehicle, view upgrades, etc.
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 8, &MenuHangar_Before);
    // before 0x435700
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 9, &MenuVehicleSelect_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 12, &MenuTrackSelect_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 13, &MenuTrack_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, ADDR_DRAW_MENU_JUMP_TABLE, 18, &MenuCantinaEntry_Before);

    return off;
}

// TEXT RENDER QUEUE FLUSHING

fn TextRender_Before() void {
    if (s.prac.get("practice_tool_enable", bool) and s.prac.get("overlay_enable", bool)) {
        practice.TextRender_Before(global.practice_mode);
    }
}

fn HookTextRender(memory: usize) usize {
    return mem.intercept_call(memory, 0x483F8B, null, &TextRender_Before);
}

// INITIALIZATION

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
    //defer s.gen.deinit();
    s.gen.add("death_speed_mod_enable", bool, false);
    s.gen.add("death_speed_min", f32, 325);
    s.gen.add("death_speed_drop", f32, 140);
    s.gen.add("rainbow_timer_enable", bool, false);
    s.gen.add("ms_timer_enable", bool, false);
    s.gen.add("default_laps", u32, 3);
    s.gen.add("default_racers", u32, 12);
    s.manager.add(&s.gen);

    s.prac = SettingsGroup.init(alloc, "practice");
    //defer s.prac.deinit();
    s.prac.add("practice_tool_enable", bool, false);
    s.prac.add("overlay_enable", bool, false);
    s.manager.add(&s.prac);

    s.mp = SettingsGroup.init(alloc, "multiplayer");
    //defer s.mp.deinit();
    s.mp.add("multiplayer_mod_enable", bool, false); // working?
    s.mp.add("patch_netplay", bool, false); // working? ups ok, coll ?
    s.mp.add("netplay_guid", bool, false); // working?
    s.mp.add("netplay_r100", bool, false); // working
    s.mp.add("patch_audio", bool, false); // FIXME: crashes
    s.mp.add("patch_fonts", bool, false); // working
    s.mp.add("fonts_dump", bool, false); // working?
    s.mp.add("patch_tga_loader", bool, false); // FIXME: need tga files to verify with
    s.mp.add("patch_trigger_display", bool, false); // working
    s.manager.add(&s.mp);

    s.manager.read_ini(alloc, "annodue/settings.ini") catch unreachable;

    // keyboard

    const kb_shift: i32 = win.GetAsyncKeyState(win.VK_SHIFT);
    const kb_shift_dn: bool = (kb_shift & win.KS_DOWN) != 0;
    global.practice_mode = kb_shift_dn;

    // general stuff

    off = HookGameLoop(off);
    off = HookGameEnd(off);
    off = HookTextRender(off);
    off = HookMenuDrawing(off);

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
