const Self = @This();

const std = @import("std");
const win = std.os.windows;

// FIXME: move most of these out
// NOTE: most of the following should be passed into the plugins by reference,
// not hardcoded into the actual hooking stuff

const settings = @import("settings.zig");
const global = @import("global.zig");
const GLOBAL_STATE = &global.GLOBAL_STATE;
const GlobalState = global.GlobalState;
const general = @import("patch_general.zig");
const practice = @import("patch_practice.zig");
const savestate = @import("patch_savestate.zig");

const win32 = @import("import/import.zig").win32;
const win32ll = win32.system.library_loader;

const dbg = @import("util/debug.zig");
const hook = @import("util/hooking.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");

// FIXME: figure out exactly where the patch gets executed on load (i.e. where
// the 'early init' happens), for documentation purposes

// FIXME: hooking (settings?) deinit causes racer process to never end, but only
// when you quit with the X button, not with the ingame quit option
// that said, again probably pointless to bother manually deallocating at the end anyway

// OKOKOKOKOK

const Hook = enum(u32) {
    Init,
    InitLate,
    Deinit,
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

const HookFnType = *const fn (state: *GlobalState, initialized: bool) callconv(.C) void;

const HookFnMapType = std.StringHashMap(HookFnType);

const HookFnSet = struct {
    initialized: bool,
    core: HookFnMapType,
    plugin: HookFnMapType,
};

const HookFn = struct {
    var initialized: bool = false;
    var data = std.enums.EnumArray(Hook, HookFnSet).initUndefined();
};

inline fn HookFnCallback(comptime hk: Hook) *const fn () void {
    const c = struct {
        const map: *HookFnSet = HookFn.data.getPtr(hk);
        fn callback() void {
            var it_core = map.core.valueIterator();
            while (it_core.next()) |f| f.*(GLOBAL_STATE, map.initialized);
            var it_plugin = map.plugin.valueIterator();
            while (it_plugin.next()) |f| f.*(GLOBAL_STATE, map.initialized);
            map.initialized = true;
        }
    };
    return &c.callback;
}

inline fn HookFnCallbackN(hk: []Hook) *const fn () void {
    const c = struct {
        fn callback() void {
            inline for (hk) |h| {
                const map: *HookFnSet = comptime HookFn.data.getPtr(h);
                var it_core = map.map.core.valueIterator();
                while (it_core.next()) |f| f.*(GLOBAL_STATE, map.initialized);
                var it_plugin = map.map.plugin.valueIterator();
                while (it_plugin.next()) |f| f.*(GLOBAL_STATE, map.initialized);
                map.map.initialized = true;
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
            .initialized = false,
            .core = HookFnMapType.init(alloc),
            .plugin = HookFnMapType.init(alloc),
        });
    }
    HookFn.initialized = true;

    var map: *HookFnMapType = undefined;

    map = &HookFn.data.getPtr(.InitLate).plugin;
    map.put("general", &general.init_late) catch unreachable;

    map = &HookFn.data.getPtr(.Deinit).core;
    map.put("settings", &settings.deinit) catch unreachable;

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

    // testing plugin loading here
    {
        dbg.ConsoleOut("hook.zig init()\n", .{}) catch unreachable;

        var buf: [1023:0]u8 = undefined;

        const cwd = std.fs.cwd();
        var dir = cwd.openIterableDir("./annodue/plugin", .{}) catch
            cwd.makeOpenPathIterable("./annodue/plugin", .{}) catch unreachable;
        defer dir.close();

        var it_dir = dir.iterate();
        while (it_dir.next() catch unreachable) |f| {
            if (f.kind != .file) continue;
            dbg.ConsoleOut("  {s}\n", .{f.name}) catch unreachable;

            _ = std.fmt.bufPrintZ(&buf, "./annodue/plugin/{s}", .{f.name}) catch unreachable;
            var lib = win32ll.LoadLibraryA(&buf);
            //defer _ = win32ll.FreeLibrary(lib);

            var it_hook = HookFn.data.iterator();
            while (it_hook.next()) |h| {
                const name = @tagName(h.key);
                var proc = win32ll.GetProcAddress(lib, name);
                if (proc == null) continue;

                map = &HookFn.data.getPtr(h.key).plugin;
                map.put(f.name, @as(HookFnType, @ptrCast(proc))) catch unreachable;
                dbg.ConsoleOut("    hooked {s} ({any})\n", .{ name, proc }) catch unreachable;
            }
        }

        dbg.ConsoleOut("\n", .{}) catch unreachable;
    }

    return off;
}

// GAME SETUP

// last function call in successful setup path
fn HookGameSetup(memory: usize) usize {
    const addr: usize = 0x4240AD;
    const len: usize = 0x4240B7 - addr;
    const off_call: usize = 0x4240AF - addr;
    return hook.detour_call(memory, addr, off_call, len, null, HookFnCallback(.InitLate));
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

// FIXME: probably just switch to fn_4240D0 (GameShutdown), not sure if hook should
// be before or after the function contents (or both); might want to make available
// opportunity to intercept e.g. the final savedata write
// WARNING: in the current scheme, core deinit happens before plugin deinit, keep this
// hook location as a stage2 or core-only deinit and use above for arbitrary deinit?
fn HookGameEnd(memory: usize) usize {
    const exit1_off: usize = 0x49CE31;
    const exit2_off: usize = 0x49CE3D;
    const exit1_len: usize = exit2_off - exit1_off - 1; // excluding retn
    const exit2_len: usize = 0x49CE48 - exit2_off - 1; // excluding retn
    var offset: usize = memory;

    offset = hook.detour(offset, exit1_off, exit1_len, null, HookFnCallback(.Deinit));
    offset = hook.detour(offset, exit2_off, exit2_len, null, HookFnCallback(.Deinit));

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
