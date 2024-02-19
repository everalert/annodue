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

const Hook = enum(u32) {
    Init,
    InitLate,
    Deinit,
    GameSetup,
    GameLoopBefore,
    GameLoopAfter,
    EarlyEngineUpdateBefore,
    EarlyEngineUpdateAfter,
    LateEngineUpdateBefore,
    LateEngineUpdateAfter,
    TimerUpdateBefore,
    TimerUpdateAfter,
    //InitHangQuadsBefore,
    InitHangQuadsAfter,
    //InitRaceQuadsBefore,
    InitRaceQuadsAfter,
    //GameEnd,
    MenuTitleScreenBefore,
    MenuStartRaceBefore,
    MenuJunkyardBefore,
    MenuRaceResultsBefore,
    MenuWattosShopBefore,
    MenuHangarBefore,
    MenuVehicleSelectBefore,
    MenuTrackSelectBefore,
    MenuTrackBefore,
    MenuCantinaEntryBefore,
    TextRenderBefore,
};

const HookFnType = std.StringHashMap(*const fn () void);

const HookFn = struct {
    var initialized: bool = false;
    var data = std.enums.EnumArray(Hook, HookFnType).initUndefined();
};

inline fn HookFnCallback(h: Hook) *const fn () void {
    const c = struct {
        const map: *HookFnType = HookFn.data.getPtr(h);
        fn callback() void {
            var it = map.valueIterator();
            while (it.next()) |f| f.*();
        }
    };
    return &c.callback;
}

// SETUP

pub fn init(alloc: std.mem.Allocator, memory: usize) usize {
    var off: usize = memory;

    off = HookGameSetup(off);
    off = HookGameLoop(off);
    off = HookEngineUpdate(off);
    off = HookTimerUpdate(off);
    off = HookInitRaceQuads(off);
    off = HookInitHangQuads(off);
    //off = HookGameEnd(off);
    off = HookTextRender(off);
    off = HookMenuDrawing(off);

    var it_hookfn = HookFn.data.iterator();
    while (it_hookfn.next()) |map| HookFn.data.set(map.key, HookFnType.init(alloc));
    HookFn.initialized = true;

    var map: *HookFnType = undefined;

    map = HookFn.data.getPtr(.InitLate);
    map.put("general", &general.init_late) catch unreachable;

    map = HookFn.data.getPtr(.EarlyEngineUpdateBefore);
    map.put("general", &general.EarlyEngineUpdate_Before) catch unreachable;
    map.put("practice", &practice.EarlyEngineUpdate_Before) catch unreachable;

    map = HookFn.data.getPtr(.EarlyEngineUpdateAfter);
    map.put("savestate", &savestate.EarlyEngineUpdate_After) catch unreachable;

    map = HookFn.data.getPtr(.InitRaceQuadsAfter);
    map.put("practice", &practice.InitRaceQuads_After) catch unreachable;

    map = HookFn.data.getPtr(.TextRenderBefore);
    map.put("general", &general.TextRender_Before) catch unreachable;
    map.put("practice", &practice.TextRender_Before) catch unreachable;
    map.put("savestate", &savestate.TextRender_Before) catch unreachable;

    return off;
}

// GAME SETUP

fn GameSetup() void {
    if (!g.initialized_late) {
        var it = HookFn.data.getPtr(.InitLate).valueIterator();
        while (it.next()) |f| f.*();
        g.initialized_late = true;
    }
    var it = HookFn.data.getPtr(.GameSetup).valueIterator();
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
    var it = HookFn.data.getPtr(.GameLoopBefore).valueIterator();
    while (it.next()) |f| f.*();
}

fn HookGameLoop(memory: usize) usize {
    return hook.intercept_call(memory, 0x49CE2A, &GameLoop_Before, HookFnCallback(.GameLoopAfter));
}

// ENGINE UPDATES

fn EarlyEngineUpdate_After() void {
    global.EarlyEngineUpdate_After();
    var it = HookFn.data.getPtr(.EarlyEngineUpdateAfter).valueIterator();
    while (it.next()) |f| f.*();
}

fn HookEngineUpdate(memory: usize) usize {
    var off: usize = memory;

    // fn_445980 case 1
    // physics updates, etc.
    off = hook.intercept_call(off, 0x445991, HookFnCallback(.EarlyEngineUpdateBefore), null);
    off = hook.intercept_call(off, 0x445A00, null, &EarlyEngineUpdate_After);

    // fn_445980 case 2
    // text processing, etc. before the actual render
    off = hook.intercept_call(off, 0x445A10, HookFnCallback(.LateEngineUpdateBefore), null);
    off = hook.intercept_call(off, 0x445A40, null, HookFnCallback(.LateEngineUpdateAfter));

    return off;
}

// GAME LOOP TIMER

fn TimerUpdate_After() void {
    global.TimerUpdate_After();
    var it = HookFn.data.getPtr(.TimerUpdateAfter).valueIterator();
    while (it.next()) |f| f.*();
}

fn HookTimerUpdate(memory: usize) usize {
    // fn_480540, in early engine update
    return hook.intercept_call(memory, 0x4459AF, HookFnCallback(.TimerUpdateBefore), &TimerUpdate_After);
}

// 'HANG' SETUP

// NOTE: disabling before fn to match RaceQuads
fn HookInitHangQuads(memory: usize) usize {
    const addr: usize = 0x454DCF;
    const len: usize = 0x454DD8 - addr;
    const off_call: usize = 0x454DD0 - addr;
    return hook.detour_call(memory, addr, off_call, len, null, HookFnCallback(.InitHangQuadsAfter));
}

// RACE SETUP

// FIXME: before fn crashes when hooked with any function contents; disabling for now
fn HookInitRaceQuads(memory: usize) usize {
    const addr: usize = 0x466D76;
    const len: usize = 0x466D81 - addr;
    const off_call: usize = 0x466D79 - addr;
    return hook.detour_call(memory, addr, off_call, len, null, HookFnCallback(.InitRaceQuadsAfter));
}

// GAME END; executable closing

// FIXME: with this hooked, process hangs on exit since adding array-indexed
// callback hashmaps, but maybe just bad hook to begin with (had the sense that
// it was actually crashing even before this)
fn GameEnd() void {
    var it_e = HookFn.data.getPtr(.GameEnd).valueIterator();
    while (it_e.next()) |f| f.*();

    var it_d = HookFn.data.getPtr(.InitLate).valueIterator();
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
    var it = HookFn.data.getPtr(.MenuTitleScreenBefore).valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuStartRace_Before() void {
    global.MenuStartRace_Before();
    var it = HookFn.data.getPtr(.MenuStartRaceBefore).valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuRaceResults_Before() void {
    global.MenuRaceResults_Before();
    var it = HookFn.data.getPtr(.MenuRaceResultsBefore).valueIterator();
    while (it.next()) |f| f.*();
}

fn MenuTrack_Before() void {
    global.MenuTrack_Before();
    var it = HookFn.data.getPtr(.MenuTrackBefore).valueIterator();
    while (it.next()) |f| f.*();
}

fn HookMenuDrawing(memory: usize) usize {
    var off: usize = memory;

    // see fn_457620 @ 0x45777F
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 1, &MenuTitleScreen_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 3, &MenuStartRace_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 4, HookFnCallback(.MenuJunkyardBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 5, &MenuRaceResults_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 7, HookFnCallback(.MenuWattosShopBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 8, HookFnCallback(.MenuHangarBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 9, HookFnCallback(.MenuVehicleSelectBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 12, HookFnCallback(.MenuTrackSelectBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 13, &MenuTrack_Before);
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 18, HookFnCallback(.MenuCantinaEntryBefore));

    return off;
}

// TEXT RENDER QUEUE FLUSHING

fn HookTextRender(memory: usize) usize {
    return hook.intercept_call(memory, 0x483F8B, null, HookFnCallback(.TextRenderBefore));
}
