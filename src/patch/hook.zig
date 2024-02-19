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

const HookFnSet = struct {
    core: HookFnType,
    plugin: HookFnType,
};

const HookFn = struct {
    var initialized: bool = false;
    var data = std.enums.EnumArray(Hook, HookFnSet).initUndefined();
};

inline fn HookFnCallback(hk: Hook) *const fn () void {
    const c = struct {
        const map: *HookFnSet = HookFn.data.getPtr(hk);
        fn callback() void {
            var it_core = map.core.valueIterator();
            while (it_core.next()) |f| f.*();
            var it_plugin = map.plugin.valueIterator();
            while (it_plugin.next()) |f| f.*();
        }
    };
    return &c.callback;
}

inline fn HookFnCallbackN(hk: []Hook) *const fn () void {
    const c = struct {
        fn callback() void {
            inline for (hk) |h| {
                const map = struct {
                    const map: *HookFnSet = HookFn.data.getPtr(h);
                };
                var it_core = map.map.core.valueIterator();
                while (it_core.next()) |f| f.*();
                var it_plugin = map.map.plugin.valueIterator();
                while (it_plugin.next()) |f| f.*();
            }
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

    var it_set = HookFn.data.iterator();
    while (it_set.next()) |set| {
        HookFn.data.set(set.key, .{
            .core = HookFnType.init(alloc),
            .plugin = HookFnType.init(alloc),
        });
    }
    HookFn.initialized = true;

    var map: *HookFnType = undefined;

    map = &HookFn.data.getPtr(.InitLate).plugin;
    map.put("general", &general.init_late) catch unreachable;

    map = &HookFn.data.getPtr(.GameLoopBefore).core;
    map.put("input", &input.update_kb) catch unreachable;

    map = &HookFn.data.getPtr(.EarlyEngineUpdateBefore).plugin;
    map.put("general", &general.EarlyEngineUpdate_Before) catch unreachable;
    map.put("practice", &practice.EarlyEngineUpdate_Before) catch unreachable;

    map = &HookFn.data.getPtr(.EarlyEngineUpdateAfter).core;
    map.put("global", &global.EarlyEngineUpdate_After) catch unreachable;
    map = &HookFn.data.getPtr(.EarlyEngineUpdateAfter).plugin;
    map.put("savestate", &savestate.EarlyEngineUpdate_After) catch unreachable;

    map = &HookFn.data.getPtr(.TimerUpdateAfter).core;
    map.put("global", &global.TimerUpdate_After) catch unreachable;

    map = &HookFn.data.getPtr(.InitRaceQuadsAfter).plugin;
    map.put("practice", &practice.InitRaceQuads_After) catch unreachable;

    map = &HookFn.data.getPtr(.MenuTitleScreenBefore).core;
    map.put("global", &global.MenuTitleScreen_Before) catch unreachable;

    map = &HookFn.data.getPtr(.MenuStartRaceBefore).core;
    map.put("global", &global.MenuStartRace_Before) catch unreachable;

    map = &HookFn.data.getPtr(.MenuRaceResultsBefore).core;
    map.put("global", &global.MenuRaceResults_Before) catch unreachable;

    map = &HookFn.data.getPtr(.MenuTrackBefore).core;
    map.put("global", &global.MenuTrack_Before) catch unreachable;

    map = &HookFn.data.getPtr(.TextRenderBefore).plugin;
    map.put("general", &general.TextRender_Before) catch unreachable;
    map.put("practice", &practice.TextRender_Before) catch unreachable;
    map.put("savestate", &savestate.TextRender_Before) catch unreachable;

    return off;
}

// GAME SETUP

fn GameSetup() void {
    if (!g.initialized_late) {
        var it = HookFn.data.getPtr(.InitLate).plugin.valueIterator();
        while (it.next()) |f| f.*();
        g.initialized_late = true;
    }
    var it = HookFn.data.getPtr(.GameSetup).plugin.valueIterator();
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

fn HookGameLoop(memory: usize) usize {
    return hook.intercept_call(
        memory,
        0x49CE2A,
        HookFnCallback(.GameLoopBefore),
        HookFnCallback(.GameLoopAfter),
    );
}

// ENGINE UPDATES

fn HookEngineUpdate(memory: usize) usize {
    var off: usize = memory;

    // fn_445980 case 1
    // physics updates, etc.
    off = hook.intercept_call(off, 0x445991, HookFnCallback(.EarlyEngineUpdateBefore), null);
    off = hook.intercept_call(off, 0x445A00, null, HookFnCallback(.EarlyEngineUpdateAfter));

    // fn_445980 case 2
    // text processing, etc. before the actual render
    off = hook.intercept_call(off, 0x445A10, HookFnCallback(.LateEngineUpdateBefore), null);
    off = hook.intercept_call(off, 0x445A40, null, HookFnCallback(.LateEngineUpdateAfter));

    return off;
}

// GAME LOOP TIMER

fn HookTimerUpdate(memory: usize) usize {
    // fn_480540, in early engine update
    return hook.intercept_call(
        memory,
        0x4459AF,
        HookFnCallback(.TimerUpdateBefore),
        HookFnCallback(.TimerUpdateAfter),
    );
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
    var it_e = HookFn.data.getPtr(.GameEnd).plugin.valueIterator();
    while (it_e.next()) |f| f.*();

    var it_d = HookFn.data.getPtr(.InitLate).plugin.valueIterator();
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

fn HookMenuDrawing(memory: usize) usize {
    var off: usize = memory;

    // see fn_457620 @ 0x45777F
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 1, HookFnCallback(.MenuTitleScreenBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 3, HookFnCallback(.MenuStartRaceBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 4, HookFnCallback(.MenuJunkyardBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 5, HookFnCallback(.MenuRaceResultsBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 7, HookFnCallback(.MenuWattosShopBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 8, HookFnCallback(.MenuHangarBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 9, HookFnCallback(.MenuVehicleSelectBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 12, HookFnCallback(.MenuTrackSelectBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 13, HookFnCallback(.MenuTrackBefore));
    off = hook.intercept_jumptable(off, rc.ADDR_DRAW_MENU_JUMPTABLE, 18, HookFnCallback(.MenuCantinaEntryBefore));

    return off;
}

// TEXT RENDER QUEUE FLUSHING

fn HookTextRender(memory: usize) usize {
    return hook.intercept_call(memory, 0x483F8B, null, HookFnCallback(.TextRenderBefore));
}
