const std = @import("std");

const settings = @import("settings.zig");
const multiplayer = @import("patch_multiplayer.zig");
const general = @import("patch_general.zig");
const practice = @import("patch_practice.zig");
const savestate = @import("patch_savestate.zig");

const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");

const ini = @import("import/import.zig").ini;
const win32 = @import("import/import.zig").win32;
const win32kb = win32.ui.input.keyboard_and_mouse;
const win32wm = win32.ui.windows_and_messaging;
const KS_DOWN: i16 = -1;
const KS_PRESSED: i16 = 1; // since last call

const VirtualAlloc = std.os.windows.VirtualAlloc;
const VirtualFree = std.os.windows.VirtualFree;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const MEM_RELEASE = std.os.windows.MEM_RELEASE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;
const WINAPI = std.os.windows.WINAPI;
const WPARAM = std.os.windows.WPARAM;
const LPARAM = std.os.windows.LPARAM;
const LRESULT = std.os.windows.LRESULT;
const HINSTANCE = std.os.windows.HINSTANCE;
const HWND = std.os.windows.HWND;

// STATE

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

const ver_major: u32 = 0;
const ver_minor: u32 = 0;
const ver_patch: u32 = 1;

const global = struct {
    var practice_mode: bool = false;
    var hwnd: ?HWND = null;
    var hinstance: ?HINSTANCE = null;
};

// ???

fn DrawMenuPracticeModeLabel() void {
    if (global.practice_mode) {
        rf.swrText_CreateEntry1(640 - 20, 16, 255, 255, 255, 255, "~F0~3~s~rPractice Mode");
    }
}

// GAME LOOP

fn GameLoop_Before() void {
    const state = struct {
        var initialized: bool = false;
    };

    input.update_kb();

    if (!state.initialized) {
        general.init_late();
        state.initialized = true;
    }

    const in_race: bool = mem.read(rc.ADDR_IN_RACE, u8) > 0;

    if (input.get_kb_pressed(.P) and
        (!(in_race and global.practice_mode)))
    {
        global.practice_mode = !global.practice_mode;
    }

    if (in_race and input.get_kb_down(.@"2") and input.get_kb_pressed(.ESCAPE)) {
        const jdge: usize = mem.deref_read(&.{ rc.ADDR_ENTITY_MANAGER_JUMP_TABLE, @intFromEnum(rc.ENTITY.Jdge) * 4, 0x10 }, usize);
        rf.TriggerLoad_InRace(jdge, rc.MAGIC_RSTR);
    }

    general.GameLoop_Before();
    practice.GameLoop_Before();
}

fn GameLoop_After() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0GameLoop_After");
}

fn HookGameLoop(memory: usize) usize {
    return mem.intercept_call(memory, 0x49CE2A, &GameLoop_Before, &GameLoop_After);
}

// ENGINE UPDATES

fn EarlyEngineUpdate_Before() void {
    //rf.swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0EarlyEngineUpdate_Before");
}

fn EarlyEngineUpdate_After() void {
    savestate.EarlyEngineUpdate_After(global.practice_mode);
    //rf.swrText_CreateEntry1(16, 24, 255, 255, 255, 255, "~F0EarlyEngineUpdate_After");
}

fn LateEngineUpdate_Before() void {
    //rf.swrText_CreateEntry1(16, 32, 255, 255, 255, 255, "~F0LateEngineUpdate_Before");
}

fn LateEngineUpdate_After() void {
    //rf.swrText_CreateEntry1(16, 40, 255, 255, 255, 255, "~F0LateEngineUpdate_After");
}

fn HookEngineUpdate(memory: usize) usize {
    var off: usize = memory;

    // fn 0x445980 case 1
    // physics updates, etc.
    off = mem.intercept_call(off, 0x445991, &EarlyEngineUpdate_Before, null);
    off = mem.intercept_call(off, 0x445A00, null, &EarlyEngineUpdate_After);

    // fn 0x445980 case 2
    // text processing, etc. before the actual render
    off = mem.intercept_call(off, 0x445A10, &LateEngineUpdate_Before, null);
    off = mem.intercept_call(off, 0x445A40, null, &LateEngineUpdate_After);

    return off;
}

// GAME END; executable closing

fn GameEnd() void {
    settings.deinit();
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
    var buf_name: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf_name, "~F0~sAnnodue {d}.{d}.{d}", .{
        ver_major,
        ver_minor,
        ver_patch,
    }) catch return;
    rf.swrText_CreateEntry1(36, 480 - 24, 255, 255, 255, 255, &buf_name);
    DrawMenuPracticeModeLabel();
}

fn MenuVehicleSelect_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuVehicleSelect_Before");
}

fn MenuStartRace_Before() void {
    DrawMenuPracticeModeLabel();
}

fn MenuJunkyard_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuJunkyard_Before");
}

fn MenuRaceResults_Before() void {
    DrawMenuPracticeModeLabel();
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
    DrawMenuPracticeModeLabel();
}

fn MenuCantinaEntry_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuCantinaEntry_Before");
}

fn HookMenuDrawing(memory: usize) usize {
    var off: usize = memory;

    // before 0x435240
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 1, &MenuTitleScreen_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 3, &MenuStartRace_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 4, &MenuJunkyard_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 5, &MenuRaceResults_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 7, &MenuWattosShop_Before);
    // before 0x______; inspect vehicle, view upgrades, etc.
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 8, &MenuHangar_Before);
    // before 0x435700
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 9, &MenuVehicleSelect_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 12, &MenuTrackSelect_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 13, &MenuTrack_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 18, &MenuCantinaEntry_Before);

    return off;
}

// TEXT RENDER QUEUE FLUSHING

fn TextRender_Before() void {
    practice.TextRender_Before(global.practice_mode);
    savestate.TextRender_Before(global.practice_mode);
}

fn HookTextRender(memory: usize) usize {
    return mem.intercept_call(memory, 0x483F8B, null, &TextRender_Before);
}

// DO THE THING!!!

export fn Patch() void {
    const mem_alloc = MEM_COMMIT | MEM_RESERVE;
    const mem_protect = PAGE_EXECUTE_READWRITE;
    const memory = VirtualAlloc(null, patch_size, mem_alloc, mem_protect) catch unreachable;
    var off: usize = @intFromPtr(memory);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // settings

    settings.init(alloc);

    // input-based launch toggles

    const kb_shift: i16 = win32kb.GetAsyncKeyState(@intFromEnum(win32kb.VK_SHIFT));
    const kb_shift_dn: bool = (kb_shift & KS_DOWN) != 0;
    global.practice_mode = kb_shift_dn;

    // hooking

    global.hwnd = mem.read(rc.ADDR_HWND, HWND);
    global.hinstance = mem.read(rc.ADDR_HINSTANCE, HINSTANCE);

    off = HookGameLoop(off);
    off = HookEngineUpdate(off);
    off = HookGameEnd(off);
    off = HookTextRender(off);
    off = HookMenuDrawing(off);

    // init: general stuff

    off = general.init(alloc, off);
    off = multiplayer.init(alloc, off);

    // debug

    if (false) {
        msg.Message("Annodue {d}.{d}.{d}", .{
            ver_major,
            ver_minor,
            ver_patch,
        }, "Patching SWE1R...", .{});
    }
}
