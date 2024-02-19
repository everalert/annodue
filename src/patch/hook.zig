const Self = @This();

const std = @import("std");
const win = std.os.windows;

// FIXME: move most of these out
// NOTE: most of the following should be passed into the plugins by reference,
// not hardcoded into the actual hooking stuff

const settings = @import("settings.zig");
const global = @import("global.zig");
const g = global.state;
const general = @import("patch_general.zig");
const practice = @import("patch_practice.zig");
const savestate = @import("patch_savestate.zig");

const hook = @import("util/hooking.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");

// FIXME: figure out exactly where the patch gets executed on load (i.e. where
// the 'early init' happens), for documentation purposes

// OKOKOKOKOK

const FnMapType = std.StringHashMap(*const fn () void);

const HookFn = struct {
    var Init: FnMapType = undefined;
    var InitLate: FnMapType = undefined;
    var Deinit: FnMapType = undefined;
    var GameSetup: FnMapType = undefined;
    var GameLoopBefore: FnMapType = undefined;
    var GameLoopAfter: FnMapType = undefined;
    var EarlyEngineUpdateBefore: FnMapType = undefined;
    var EarlyEngineUpdateAfter: FnMapType = undefined;
    var LateEngineUpdateBefore: FnMapType = undefined;
    var LateEngineUpdateAfter: FnMapType = undefined;
    var TimerUpdateBefore: FnMapType = undefined;
    var TimerUpdateAfter: FnMapType = undefined;
    //var InitHangQuadsBefore: FnMapType = undefined;
    var InitHangQuadsAfter: FnMapType = undefined;
    //var InitRaceQuadsBefore: FnMapType = undefined;
    var InitRaceQuadsAfter: FnMapType = undefined;
    var GameEnd: FnMapType = undefined;
    var MenuTitleScreenBefore: FnMapType = undefined;
    var MenuStartRaceBefore: FnMapType = undefined;
    var MenuJunkyardBefore: FnMapType = undefined;
    var MenuRaceResultsBefore: FnMapType = undefined;
    var MenuWattosShopBefore: FnMapType = undefined;
    var MenuHangarBefore: FnMapType = undefined;
    var MenuVehicleSelectBefore: FnMapType = undefined;
    var MenuTrackSelectBefore: FnMapType = undefined;
    var MenuTrackBefore: FnMapType = undefined;
    var MenuCantinaEntryBefore: FnMapType = undefined;
    var TextRenderBefore: FnMapType = undefined;
};

// SETUP

pub fn init(alloc: std.mem.Allocator, memory: usize) usize {
    var off: usize = memory;

    off = HookGameSetup(off);
    off = HookGameLoop(off);
    off = HookEngineUpdate(off);
    off = HookTimerUpdate(off);
    off = HookInitRaceQuads(off);
    off = HookInitHangQuads(off);
    off = HookGameEnd(off);
    off = HookTextRender(off);
    off = HookMenuDrawing(off);

    HookFn.Init = FnMapType.init(alloc);
    HookFn.InitLate = FnMapType.init(alloc);
    HookFn.InitLate.put("general", &general.init_late) catch unreachable;
    HookFn.Deinit = FnMapType.init(alloc);
    HookFn.GameSetup = FnMapType.init(alloc);
    HookFn.GameLoopBefore = FnMapType.init(alloc);
    HookFn.GameLoopAfter = FnMapType.init(alloc);
    HookFn.EarlyEngineUpdateBefore = FnMapType.init(alloc);
    HookFn.EarlyEngineUpdateBefore.put("general", &general.EarlyEngineUpdate_Before) catch unreachable;
    HookFn.EarlyEngineUpdateBefore.put("practice", &practice.EarlyEngineUpdate_Before) catch unreachable;
    HookFn.EarlyEngineUpdateAfter = FnMapType.init(alloc);
    HookFn.EarlyEngineUpdateAfter.put("savestate", &savestate.EarlyEngineUpdate_After) catch unreachable;
    HookFn.LateEngineUpdateBefore = FnMapType.init(alloc);
    HookFn.LateEngineUpdateAfter = FnMapType.init(alloc);
    HookFn.TimerUpdateBefore = FnMapType.init(alloc);
    HookFn.TimerUpdateAfter = FnMapType.init(alloc);
    //HookFn.InitHangQuadsBefore = FnMapType.init(alloc);
    HookFn.InitHangQuadsAfter = FnMapType.init(alloc);
    //HookFn.InitRaceQuadsBefore = FnMapType.init(alloc);
    HookFn.InitRaceQuadsAfter = FnMapType.init(alloc);
    HookFn.GameEnd = FnMapType.init(alloc);
    HookFn.MenuTitleScreenBefore = FnMapType.init(alloc);
    HookFn.MenuStartRaceBefore = FnMapType.init(alloc);
    HookFn.MenuJunkyardBefore = FnMapType.init(alloc);
    HookFn.MenuRaceResultsBefore = FnMapType.init(alloc);
    HookFn.MenuWattosShopBefore = FnMapType.init(alloc);
    HookFn.MenuHangarBefore = FnMapType.init(alloc);
    HookFn.MenuVehicleSelectBefore = FnMapType.init(alloc);
    HookFn.MenuTrackSelectBefore = FnMapType.init(alloc);
    HookFn.MenuTrackBefore = FnMapType.init(alloc);
    HookFn.MenuCantinaEntryBefore = FnMapType.init(alloc);
    HookFn.TextRenderBefore = FnMapType.init(alloc);
    HookFn.TextRenderBefore.put("general", &general.TextRender_Before) catch unreachable;
    HookFn.TextRenderBefore.put("practice", &practice.TextRender_Before) catch unreachable;
    HookFn.TextRenderBefore.put("savestate", &savestate.TextRender_Before) catch unreachable;

    return off;
}

// GAME SETUP

fn GameSetup() void {
    if (!g.initialized_late) {
        var it = HookFn.InitLate.valueIterator();
        while (it.next()) |f| f.*();
        g.initialized_late = true;
    }
    var it = HookFn.GameSetup.valueIterator();
    while (it.next()) |f| f.*();
}

// last function call in successful setup path
fn HookGameSetup(memory: usize) usize {
    const addr: usize = 0x4240AD;
    const len: usize = 0x4240B7 - addr;
    const off_call: usize = 0x4240AF - addr;
    return hook.detour_call(memory, addr, off_call, len, null, &GameSetup);
}

// GAME LOOP

fn GameLoop_Before() void {
    input.update_kb();
    var it = HookFn.GameLoopBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn GameLoop_After() void {
    var it = HookFn.GameLoopAfter.valueIterator();
    while (it.next()) |f| f.*();
}

fn HookGameLoop(memory: usize) usize {
    return hook.intercept_call(memory, 0x49CE2A, &GameLoop_Before, &GameLoop_After);
}

// ENGINE UPDATES

fn EarlyEngineUpdate_Before() void {
    var it = HookFn.EarlyEngineUpdateBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn EarlyEngineUpdate_After() void {
    global.EarlyEngineUpdate_After();
    var it = HookFn.EarlyEngineUpdateAfter.valueIterator();
    while (it.next()) |f| f.*();
}

fn LateEngineUpdate_Before() void {
    var it = HookFn.LateEngineUpdateBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn LateEngineUpdate_After() void {
    var it = HookFn.LateEngineUpdateAfter.valueIterator();
    while (it.next()) |f| f.*();
}

fn HookEngineUpdate(memory: usize) usize {
    var off: usize = memory;

    // fn_445980 case 1
    // physics updates, etc.
    off = hook.intercept_call(off, 0x445991, &EarlyEngineUpdate_Before, null);
    off = hook.intercept_call(off, 0x445A00, null, &EarlyEngineUpdate_After);

    // fn_445980 case 2
    // text processing, etc. before the actual render
    off = hook.intercept_call(off, 0x445A10, &LateEngineUpdate_Before, null);
    off = hook.intercept_call(off, 0x445A40, null, &LateEngineUpdate_After);

    return off;
}

// GAME LOOP TIMER

fn TimerUpdate_Before() void {
    var it = HookFn.TimerUpdateBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn TimerUpdate_After() void {
    global.TimerUpdate_After();
    var it = HookFn.TimerUpdateAfter.valueIterator();
    while (it.next()) |f| f.*();
}

fn HookTimerUpdate(memory: usize) usize {
    // fn_480540, in early engine update
    return hook.intercept_call(memory, 0x4459AF, &TimerUpdate_Before, &TimerUpdate_After);
}

// 'HANG' SETUP

// NOTE: disabling to match RaceQuads
fn InitHangQuads_Before() void {
    var it = HookFn.InitHangQuadsBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn InitHangQuads_After() void {
    var it = HookFn.InitHangQuadsAfter.valueIterator();
    while (it.next()) |f| f.*();
}

fn HookInitHangQuads(memory: usize) usize {
    const addr: usize = 0x454DCF;
    const len: usize = 0x454DD8 - addr;
    const off_call: usize = 0x454DD0 - addr;
    return hook.detour_call(memory, addr, off_call, len, null, &InitHangQuads_After);
}

// RACE SETUP

// FIXME: crashes when hooked with any function contents; disabling for now
fn InitRaceQuads_Before() void {
    var it = HookFn.InitRaceQuadsBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn InitRaceQuads_After() void {
    var it = HookFn.InitRaceQuadsAfter.valueIterator();
    while (it.next()) |f| f.*();
}

fn HookInitRaceQuads(memory: usize) usize {
    const addr: usize = 0x466D76;
    const len: usize = 0x466D81 - addr;
    const off_call: usize = 0x466D79 - addr;
    return hook.detour_call(memory, addr, off_call, len, null, &InitRaceQuads_After);
}

// GAME END; executable closing

fn GameEnd() void {
    var it_e = HookFn.GameEnd.valueIterator();
    while (it_e.next()) |f| f.*();

    var it_d = HookFn.InitLate.valueIterator();
    while (it_d.next()) |f| f.*();
    settings.deinit();
}

fn HookGameEnd(memory: usize) usize {
    const exit1_off: usize = 0x49CE31;
    const exit2_off: usize = 0x49CE3D;
    const exit1_len: usize = exit2_off - exit1_off - 1; // excluding retn
    const exit2_len: usize = 0x49CE48 - exit2_off - 1; // excluding retn
    var offset: usize = memory;

    offset = hook.detour(offset, exit1_off, exit1_len, null, &GameEnd);
    offset = hook.detour(offset, exit2_off, exit2_len, null, &GameEnd);

    return offset;
}

// MENU DRAW CALLS in 'Hang' callback0x14

fn MenuTitleScreen_Before() void {
    global.MenuTitleScreen_Before();
    var it = HookFn.MenuTitleScreenBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuVehicleSelect_Before() void {
    var it = HookFn.MenuVehicleSelectBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuStartRace_Before() void {
    global.MenuStartRace_Before();
    var it = HookFn.MenuStartRaceBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuJunkyard_Before() void {
    var it = HookFn.MenuJunkyardBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuRaceResults_Before() void {
    global.MenuRaceResults_Before();
    var it = HookFn.MenuRaceResultsBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuWattosShop_Before() void {
    var it = HookFn.MenuWattosShopBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuHangar_Before() void {
    var it = HookFn.MenuHangarBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuTrackSelect_Before() void {
    var it = HookFn.MenuTrackSelectBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuTrack_Before() void {
    global.MenuTrack_Before();
    var it = HookFn.MenuTrackBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuCantinaEntry_Before() void {
    var it = HookFn.MenuCantinaEntryBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn HookMenuDrawing(memory: usize) usize {
    var off: usize = memory;

    // see fn_457620 @ 0x45777F
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 1, &MenuTitleScreen_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 3, &MenuStartRace_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 4, &MenuJunkyard_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 5, &MenuRaceResults_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 7, &MenuWattosShop_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 8, &MenuHangar_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 9, &MenuVehicleSelect_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 12, &MenuTrackSelect_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 13, &MenuTrack_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 18, &MenuCantinaEntry_Before);

    return off;
}

// TEXT RENDER QUEUE FLUSHING

fn TextRender_Before() void {
    var it = HookFn.TextRenderBefore.valueIterator();
    while (it.next()) |f| f.*();
}

fn HookTextRender(memory: usize) usize {
    return hook.intercept_call(memory, 0x483F8B, null, &TextRender_Before);
}
