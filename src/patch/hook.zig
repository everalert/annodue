const Self = @This();

const std = @import("std");
const win = std.os.windows;

// FIXME: move most of these out
// NOTE: most of the following should be passed into the plugins by reference,
// not hardcoded into the actual hooking stuff

const settings = @import("settings.zig");
const global = @import("global.zig");
const GlobalState = global.GlobalState;
const GLOBAL_STATE = &global.GLOBAL_STATE;
const GlobalVTable = global.GlobalVTable;
const GLOBAL_VTABLE = &global.GLOBAL_VTABLE;
const PLUGIN_VERSION = global.PLUGIN_VERSION;
const practice = @import("patch_practice.zig");

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

const Required = enum(u32) {
    PluginName,
    PluginVersion,
    PluginCompatibilityVersion,
    // TODO: flags for cosmetic, QOL, etc. (some ignored for non-whitelisted plugins)
    //PluginCategoryFlags,
    OnInit,
    OnInitLate,
    OnDeinit,
    //OnEnable,
    //OnDisable,
};

const HookFnType = *const fn (state: *GlobalState, vtable: *GlobalVTable, initialized: bool) callconv(.C) void;

inline fn RequiredFnType(comptime f: Required) type {
    return switch (f) {
        .PluginName => *const fn () callconv(.C) [*:0]const u8,
        .PluginVersion => *const fn () callconv(.C) [*:0]const u8,
        .PluginCompatibilityVersion => *const fn () callconv(.C) u32,
        //.PluginCategoryFlags => *const fn () callconv(.C) u32,
        else => HookFnType,
    };
}

inline fn RequiredFnMapType(comptime f: Required) type {
    return std.StringHashMap(RequiredFnType(f));
}

const Hook = enum(u32) {
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

const HookFnMapType = std.StringHashMap(HookFnType);

inline fn PluginFnSet(comptime T: type) type {
    return struct {
        initialized: bool,
        core: T,
        plugin: T,
    };
}

const HookFnSet = PluginFnSet(HookFnMapType);

const PluginFn = struct {
    var initialized: bool = false;
    var hooks = std.enums.EnumArray(Hook, HookFnSet).initUndefined();
    // FIXME: comptime generation
    var PluginName: PluginFnSet(RequiredFnMapType(.PluginName)) = undefined;
    var PluginVersion: PluginFnSet(RequiredFnMapType(.PluginVersion)) = undefined;
    var PluginCompatibilityVersion: PluginFnSet(RequiredFnMapType(.PluginCompatibilityVersion)) = undefined;
    var OnInit: PluginFnSet(RequiredFnMapType(.OnInit)) = undefined;
    var OnInitLate: PluginFnSet(RequiredFnMapType(.OnInitLate)) = undefined;
    var OnDeinit: PluginFnSet(RequiredFnMapType(.OnDeinit)) = undefined;
};

inline fn RequiredFnCallback(comptime req: Required) *const fn () void {
    const c = struct {
        const map: *HookFnSet = &@field(PluginFn, @tagName(req));
        fn callback() void {
            var it_core = map.core.valueIterator();
            while (it_core.next()) |f| f.*(GLOBAL_STATE, GLOBAL_VTABLE, map.initialized);
            var it_plugin = map.plugin.valueIterator();
            while (it_plugin.next()) |f| f.*(GLOBAL_STATE, GLOBAL_VTABLE, map.initialized);
            map.initialized = true;
        }
    };
    return &c.callback;
}

inline fn HookFnCallback(comptime hk: Hook) *const fn () void {
    const c = struct {
        const map: *HookFnSet = PluginFn.hooks.getPtr(hk);
        fn callback() void {
            var it_core = map.core.valueIterator();
            while (it_core.next()) |f| f.*(GLOBAL_STATE, GLOBAL_VTABLE, map.initialized);
            var it_plugin = map.plugin.valueIterator();
            while (it_plugin.next()) |f| f.*(GLOBAL_STATE, GLOBAL_VTABLE, map.initialized);
            map.initialized = true;
        }
    };
    return &c.callback;
}

//inline fn HookFnCallbackN(hk: []Hook) *const fn () void {
//    const c = struct {
//        fn callback() void {
//            inline for (hk) |h| {
//                const map: *HookFnSet = comptime PluginFn.hooks.getPtr(h);
//                var it_core = map.map.core.valueIterator();
//                while (it_core.next()) |f| f.*(GLOBAL_STATE, map.initialized);
//                var it_plugin = map.map.plugin.valueIterator();
//                while (it_plugin.next()) |f| f.*(GLOBAL_STATE, map.initialized);
//                map.map.initialized = true;
//            }
//        }
//    };
//    return &c.callback;
//}

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
    global.GLOBAL_STATE.patch_offset = off;

    var it_hset = PluginFn.hooks.iterator();
    while (it_hset.next()) |set| {
        PluginFn.hooks.set(set.key, .{
            .initialized = false,
            .core = HookFnMapType.init(alloc),
            .plugin = HookFnMapType.init(alloc),
        });
    }
    inline for (@typeInfo(Required).Enum.fields) |f| {
        const v: Required = @enumFromInt(f.value);
        @field(PluginFn, f.name) = .{
            .initialized = false,
            .core = RequiredFnMapType(v).init(alloc),
            .plugin = RequiredFnMapType(v).init(alloc),
        };
    }
    PluginFn.initialized = true;

    var map: *HookFnMapType = undefined;

    // testing plugin loading here
    {
        dbg.ConsoleOut("hook.zig init()\n", .{}) catch unreachable;

        var buf: [1023:0]u8 = undefined;

        const cwd = std.fs.cwd();
        var dir = cwd.openIterableDir("./annodue/plugin", .{}) catch
            cwd.makeOpenPathIterable("./annodue/plugin", .{}) catch unreachable;
        defer dir.close();

        var it_dir = dir.iterate();
        while (it_dir.next() catch unreachable) |file| {
            if (file.kind != .file) continue;
            dbg.ConsoleOut("  {s}\n", .{file.name}) catch unreachable;

            _ = std.fmt.bufPrintZ(&buf, "./annodue/plugin/{s}", .{file.name}) catch unreachable;
            var lib = win32ll.LoadLibraryA(&buf);
            //defer _ = win32ll.FreeLibrary(lib);
            dbg.ConsoleOut("    DLL loaded\n", .{}) catch unreachable;

            // required callbacks
            var valid: bool = true;
            const fields = comptime std.enums.values(Required);
            inline for (fields) |field| {
                const n = @tagName(field);
                var proc = win32ll.GetProcAddress(lib, n);
                if (proc == null) {
                    dbg.ConsoleOut("    {s} not found, DLL unloaded\n", .{n}) catch unreachable;
                    valid = false;
                    break;
                }
                const func = @as(RequiredFnType(field), @ptrCast(proc));
                if (field == .PluginCompatibilityVersion and func() != PLUGIN_VERSION) {
                    dbg.ConsoleOut(
                        "    Plugin version not compatible, DLL unloaded\n",
                        .{},
                    ) catch unreachable;
                    valid = false;
                    break;
                }
                @field(PluginFn, @tagName(field)).plugin.put(file.name, func) catch unreachable;
                dbg.ConsoleOut("    hooked {s} ({any})\n", .{ n, proc }) catch unreachable;
            }
            if (!valid) {
                inline for (fields) |used_field|
                    _ = @field(PluginFn, @tagName(used_field)).plugin.remove(file.name);
                _ = win32ll.FreeLibrary(lib);
                continue;
            }
            if (@field(PluginFn, @tagName(.OnInit)).plugin.get(file.name)) |func_init|
                func_init(GLOBAL_STATE, GLOBAL_VTABLE, false);

            // optional/hook callbacks
            var it_hook = PluginFn.hooks.iterator();
            while (it_hook.next()) |h| {
                const name = @tagName(h.key);
                var proc = win32ll.GetProcAddress(lib, name);
                if (proc == null) continue;

                map = &PluginFn.hooks.getPtr(h.key).plugin;
                map.put(file.name, @as(HookFnType, @ptrCast(proc))) catch unreachable;
                dbg.ConsoleOut("    hooked {s} ({any})\n", .{ name, proc }) catch unreachable;
            }
        }

        dbg.ConsoleOut("\n", .{}) catch unreachable;
    }

    map = &PluginFn.OnDeinit.core;
    map.put("settings", &settings.deinit) catch unreachable;

    map = &PluginFn.hooks.getPtr(.GameLoopBefore).core;
    map.put("input", &input.update_kb) catch unreachable;

    map = &PluginFn.hooks.getPtr(.EarlyEngineUpdateAfter).core;
    map.put("global", &global.EarlyEngineUpdate_After) catch unreachable;

    map = &PluginFn.hooks.getPtr(.TimerUpdateAfter).core;
    map.put("global", &global.TimerUpdate_After) catch unreachable;

    map = &PluginFn.hooks.getPtr(.InitRaceQuadsAfter).plugin;
    map.put("practice", &practice.InitRaceQuads_After) catch unreachable;

    map = &PluginFn.hooks.getPtr(.MenuTitleScreenBefore).core;
    map.put("global", &global.MenuTitleScreen_Before) catch unreachable;

    map = &PluginFn.hooks.getPtr(.MenuStartRaceBefore).core;
    map.put("global", &global.MenuStartRace_Before) catch unreachable;

    map = &PluginFn.hooks.getPtr(.MenuRaceResultsBefore).core;
    map.put("global", &global.MenuRaceResults_Before) catch unreachable;

    map = &PluginFn.hooks.getPtr(.MenuTrackBefore).core;
    map.put("global", &global.MenuTrack_Before) catch unreachable;

    map = &PluginFn.hooks.getPtr(.TextRenderBefore).plugin;
    map.put("practice", &practice.TextRender_Before) catch unreachable;

    off = global.GLOBAL_STATE.patch_offset;
    return off;
}

// GAME SETUP

// last function call in successful setup path
fn HookGameSetup(memory: usize) usize {
    const addr: usize = 0x4240AD;
    const len: usize = 0x4240B7 - addr;
    const off_call: usize = 0x4240AF - addr;
    return hook.detour_call(memory, addr, off_call, len, null, RequiredFnCallback(.OnInitLate));
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

    offset = hook.detour(offset, exit1_off, exit1_len, null, RequiredFnCallback(.OnDeinit));
    offset = hook.detour(offset, exit2_off, exit2_len, null, RequiredFnCallback(.OnDeinit));

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
