const Self = @This();

const BuildOptions = @import("BuildOptions");

const std = @import("std");
const SemVer = std.SemanticVersion;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const w32 = @import("zigwin32");
const HINSTANCE = w32.foundation.HINSTANCE;
const MAX_PATH = w32.foundation.MAX_PATH;
const MAX_PATH_SENTINEL = MAX_PATH - 1;
const CopyFileA = w32.storage.file_system.CopyFileA;
const LoadLibraryA = w32.system.library_loader.LoadLibraryA;
const FreeLibrary = w32.system.library_loader.FreeLibrary;
const GetProcAddress = w32.system.library_loader.GetProcAddress;

const core = @import("core.zig");
const CoreAllocator = core.Allocator;
const GLOBAL_STATE = &core.Global.GLOBAL_STATE;
const GLOBAL_FUNCTION = &core.Global.GLOBAL_FUNCTION;

const app = @import("../appinfo.zig");
const GlobalFn = app.GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = app.COMPATIBILITY_VERSION;

const hot_reload = @import("../util/hot_reload.zig");
const hook = @import("../util/hooking.zig");
const mem = @import("../util/memory.zig");
const dbg = @import("../util/debug.zig");

const SettingHandle = @import("ASettings.zig").Handle;
const SettingValue = @import("ASettings.zig").ASettingSent.Value;
const Setting = @import("ASettings.zig").ASettingSent;

const r = @import("racer");
const reh = r.Entity.Hang;
const rti = r.Time;

// TODO: switch to Sha256 for perf?
const Sha512 = std.crypto.hash.sha2.Sha512;
const plugin_hashes_data = @embedFile("hashfile");
const plugin_hashes_len: u32 = (plugin_hashes_data.len - 4) / 64;
const plugin_hashes: *align(1) const [plugin_hashes_len][64]u8 = std.mem.bytesAsValue([plugin_hashes_len][64]u8, plugin_hashes_data[4..]);

// TODO: figure out exactly where the patch gets executed on load (i.e. where
// the 'early init' happens), for documentation purposes

// FIXME: hooking (settings?) deinit causes racer process to never end, but only
// when you quit with the X button, not with the ingame quit option
// that said, again probably pointless to bother manually deallocating at the end anyway

// OKOKOKOKOK

pub const PLUGIN_FUNCTION_VERSION = 1;

const Plugin = plugin: {
    const stdf = .{
        .{ "Handle", ?HINSTANCE },
        .{ "Initialized", bool },
        .{ "OwnerId", u16 },
    };
    const ev = std.enums.values(PluginExportFn);
    var fields: [stdf.len + ev.len]std.builtin.Type.StructField = undefined;

    for (stdf, 0..) |f, i| {
        fields[i] = .{
            .name = f[0],
            .type = f[1],
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }
    for (ev, stdf.len..) |f, i| {
        fields[i] = .{
            .name = @tagName(f),
            .type = PluginExportFnType(f),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    break :plugin @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = fields[0..],
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = false,
    } });
};

fn PluginExportFnType(comptime f: PluginExportFn) type {
    return switch (f) {
        .PluginName, .PluginVersion => ?*const fn () callconv(.C) [*:0]const u8,
        .PluginCompatibilityVersion => ?*const fn () callconv(.C) u32,
        //.PluginCategoryFlags => *const fn () callconv(.C) u32,
        .OnPluginInitA, .OnPluginInitLateA, .OnPluginDeinitA => ?*const fn (u16) callconv(.C) void,
        else => ?*const fn (*GlobalFn) callconv(.C) void,
    };
}

const PluginExportFn = enum(u32) {
    // Setup/Meta Functions
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
    //OnPluginInitB,
    OnPluginInitA,
    //OnPluginInitLateB,
    OnPluginInitLateA,
    //OnPluginDeinitB,
    OnPluginDeinitA,

    // Hook Functions
    GameLoopB,
    GameLoopA,
    EarlyEngineUpdateB,
    EarlyEngineUpdateA,
    LateEngineUpdateB,
    LateEngineUpdateA,
    EngineEntityUpdateB,
    //EngineEntityUpdateA,
    //EngineUpdateStage14B,
    EngineUpdateStage14A,
    //EngineUpdateStage18B,
    EngineUpdateStage18A,
    //EngineUpdateStage1CB,
    EngineUpdateStage1CA,
    //EngineUpdateStage20B,
    EngineUpdateStage20A,
    TimerUpdateB,
    TimerUpdateA,
    InputUpdateB,
    InputUpdateA,
    InputUpdateControlsB,
    InputUpdateControlsA,
    InputUpdateKeyboardB,
    InputUpdateKeyboardA,
    InputUpdateJoysticksB,
    InputUpdateJoysticksA,
    InputUpdateMouseB,
    InputUpdateMouseA,
    //InitHangQuadsB,
    InitHangQuadsA,
    //InitRaceQuadsB,
    InitRaceQuadsA,
    //EventJdgeBegnB,
    //EventJdgeBegnA,
    MenuTitleScreenB,
    MenuStartRaceB,
    MenuJunkyardB,
    MenuRaceResultsB,
    MenuWattosShopB,
    MenuHangarB,
    MenuVehicleSelectB,
    MenuTrackSelectB,
    MenuTrackB,
    MenuCantinaEntryB,
    Draw2DB,
    Draw2DA,
    TextRenderB, // TODO: deprecate
    TextRenderA, // TODO: deprecate
    MapRenderB,
    MapRenderA,
    RenderSceneBeginB,
    RenderSceneBeginA,
    RenderSceneEndB,
    RenderSceneEndA,
};

// TODO: directory-monitoring hot_reload impl (need for core menu impl)
// TODO: review plugin-related loops (including hot_reload impl); probably not
//  a performance concern at all given the current array sizes, but there is
//  a lot of looping over "nothing" when calling plugin functions and this grows
//  at N*M for every plugin and callback hook added
// TODO: owner range limiting
pub const PluginState = struct {
    var core: ArrayList(Plugin) = undefined;
    var plugins: [PLUGIN_MAX]Plugin = undefined;
    var plugins_used: [PLUGIN_MAX]bool = std.mem.zeroes([PLUGIN_MAX]bool);
    var plugins_count: u32 = 0;
    var plugins_toast: [PLUGIN_MAX]HotReloadPluginHandle = undefined;
    var plugins_toast_count: u32 = 0;
    var plugins_reloader: HotReloadPlugin = undefined;
    var owners_core: u16 = 0x0000;
    var owners_user: u16 = 0x0800;
    var working_owner: u16 = 0;

    var h_s_hot_reload: ?SettingHandle = null;
    var s_hot_reload: bool = true;

    const PLUGIN_MAX = 64;
    const HotReloadPluginHandle = u32;
    const HotReloadPlugin = hot_reload.HotReload(HotReloadPluginHandle, PLUGIN_MAX);

    pub fn workingOwner() u16 {
        return working_owner;
    }

    pub fn workingOwnerIsSystem() bool {
        return working_owner < 0x0800;
    }

    fn LoadPluginResultCallback(handle: HotReloadPluginHandle, _: [:0]const u8, _: [:0]const u8, result: bool) void {
        defer assert(plugins_toast_count <= PLUGIN_MAX);

        if (result) blk: {
            if (plugins_toast_count == PLUGIN_MAX) break :blk;
            plugins_toast[plugins_toast_count] = handle;
            plugins_toast_count += 1;
        } else {
            plugins_used[handle] = false;
            plugins_count -= 1;
        }
    }

    // TODO: ascertain the necessity of `Plugin.Initialized`; cursory review seems
    //  to suggest that p.Initialized basically just performed the same task as
    //  `PluginState.plugins_used` does now, but unsure if there will be any ill
    //  effects if removed outright
    // TODO: ?? log stuff at all the failure/exit points?
    // TODO: ignore hash check to re-enable hot reloading for dev and unofficial plugins
    //  only, probably want modal system in place properly first
    // TODO: possibly assert that this fully sets all fields and acts as an initializer
    //  to a plugin struct, not just something that hooks up the fn refs
    // TODO: OnLoad, OnUnload, OnEnable, OnDisable
    // TODO: also stuff for loading and unloading based on watching the directory, outside of
    //  updating already loaded plugins
    // TODO: allow OnPluginDeinit for user-plugins; needs protections and to communicate which plugin
    // NOTE: assumes index is allocated and initialized, to allow different
    //  ways of handling the backing data
    /// callback for Plugin hot_reload impl; the file given is assumed to be newer
    /// if reloading, as the newness is checked by hot_reload
    /// @return     null = no change, true = (re)loaded, false = rejected
    ///             guarantee of no dangling handles on failure
    fn LoadPluginCallback(handle: HotReloadPluginHandle, filepath: [:0]const u8, filename: [:0]const u8) bool {
        assert(handle < PLUGIN_MAX);
        assert(plugins_used[handle] == true or (!plugins_used[handle] and !plugins[handle].Initialized));
        // FIXME: this would fail on initial load, but it makes more sense as an
        //  assert; maybe split loading and unloading in hot_reload api to help
        //  simplify the impl overall
        //assert(plugins_used[handle] == true);

        const p: *Plugin = &plugins[handle];

        // do we need to unload anything
        if (p.Handle) |h| {
            p.OnDeinit.?(GLOBAL_FUNCTION);
            PluginFnOnPluginInit(.OnPluginDeinitA, p.OwnerId);
            _ = FreeLibrary(h);
        }

        // FIXME: to remove; will be embedding stock plugins moving forward
        if (BuildOptions.BUILD_MODE != .Developer) blk: {
            const this_hash = getFileSha512(filepath) catch return false;
            for (plugin_hashes) |hash|
                if (std.mem.eql(u8, &this_hash, &hash))
                    break :blk;
            return false;
        }

        var buf_tmp: [MAX_PATH_SENTINEL:0]u8 = undefined;
        const filename_no_ext = filename[0 .. filename.len - 4];
        _ = std.fmt.bufPrintZ(&buf_tmp, "./annodue/tmp/plugin/{s}.tmp.dll", .{filename_no_ext}) catch
            return false;

        // now we ball

        _ = CopyFileA(filepath, &buf_tmp, 0);
        p.Handle = LoadLibraryA(&buf_tmp);
        // NOTE: handled by hot_reload; maybe add LoadTime to hot_reload as a way of
        //  differentiating successful loads with file checks
        //p.WriteTime = fd1.ftLastWriteTime;

        const fields = comptime std.enums.values(PluginExportFn);
        inline for (fields) |field| {
            const process = GetProcAddress(p.Handle, @tagName(field));
            @field(p, @tagName(field)) = if (process) |proc| @ptrCast(proc) else null;
        }

        // required functions and metadata
        if (p.PluginName == null or
            p.PluginVersion == null or
            SemVer.parse(p.PluginVersion.?()[0..std.mem.len(p.PluginVersion.?())]) == error.InvalidVersion or
            p.PluginCompatibilityVersion == null or
            p.PluginCompatibilityVersion.?() != COMPATIBILITY_VERSION or
            p.OnInit == null or
            p.OnInitLate == null or
            p.OnDeinit == null or
            // only allowed in core
            p.OnPluginInitA != null or
            p.OnPluginInitLateA != null or
            p.OnPluginDeinitA != null)
        {
            _ = FreeLibrary(p.Handle);
            p.Initialized = false;
            return false;
        }

        p.OwnerId = PluginState.owners_user;
        PluginState.owners_user += 1;
        PluginState.working_owner = p.OwnerId;
        p.OnInit.?(GLOBAL_FUNCTION);
        PluginFnOnPluginInit(.OnPluginInitA, p.OwnerId);
        if (GLOBAL_STATE.init_late_passed) p.OnInitLate.?(GLOBAL_FUNCTION);
        p.Initialized = true;
        return true;
    }
};

pub fn PluginFnCallback(comptime ex: PluginExportFn) *const fn () void {
    const c = struct {
        fn callback() void {
            for (PluginState.core.items) |p| {
                PluginState.working_owner = p.OwnerId;
                if (@field(p, @tagName(ex))) |f| {
                    f(GLOBAL_FUNCTION);
                    switch (ex) {
                        .OnInitLate => PluginFnOnPluginInit(.OnPluginInitLateA, PluginState.working_owner),
                        else => {},
                    }
                }
            }
            for (PluginState.plugins_used, 0..) |used, i| {
                if (!used) continue;
                const p: *const Plugin = &PluginState.plugins[i];
                PluginState.working_owner = p.OwnerId;
                if (@field(p, @tagName(ex))) |f| {
                    f(GLOBAL_FUNCTION);
                    switch (ex) {
                        .OnInitLate => PluginFnOnPluginInit(.OnPluginInitLateA, PluginState.working_owner),
                        else => {},
                    }
                }
            }
        }
    };
    return &c.callback;
}

//// TODO: generalize for OnPluginInit etc.
//fn PluginFnOnPluginDeinit(owner: u16) void {
//    for (PluginState.core.items) |p| {
//        if (p.OwnerId == owner) continue;
//        PluginState.working_owner = p.OwnerId;
//        if (@field(p, @tagName(.OnPluginDeinit))) |f| f(owner);
//    }
//    for (PluginState.plugin.items) |p| {
//        if (p.OwnerId == owner) continue;
//        PluginState.working_owner = p.OwnerId;
//        if (@field(p, @tagName(.OnPluginDeinit))) |f| f(owner);
//    }
//}
pub fn PluginFnOnPluginInit(comptime ex: PluginExportFn, owner: u16) void {
    comptime if (ex != .OnPluginInitA and
        ex != .OnPluginInitLateA and
        ex != .OnPluginDeinitA) @compileError("invalid plugin export fn");

    for (PluginState.core.items) |p| {
        if (p.OwnerId == owner) continue;
        PluginState.working_owner = p.OwnerId;
        if (@field(p, @tagName(ex))) |f| f(owner);
    }
    // TODO: system to allow any plugin to act on any other plugin's init-ing safely
    //for (PluginState.plugin.items) |p| {
    //    if (p.OwnerId == owner) continue;
    //    PluginState.working_owner = p.OwnerId;
    //    if (@field(p, @tagName(ex))) |f| f(owner);
    //}
}

fn PluginFnCallback1_stub(_: u32) void {}

// MISC

// TODO: move to lib, share with generate_safe_plugin_hash_file.zig
fn getFileSha512(filename: []u8) ![Sha512.digest_length]u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var sha512 = Sha512.init(.{});
    var file_br = std.io.bufferedReader(file.reader());
    const file_r = file_br.reader();

    var buf: [std.mem.page_size]u8 = undefined;
    var n = try file_r.read(&buf);
    while (n != 0) {
        sha512.update(buf[0..n]);
        n = try file_r.read(&buf);
    }

    return sha512.finalResult();
}

// SETUP

pub fn init() void {
    defer assert(PluginState.plugins_count == std.mem.count(bool, &PluginState.plugins_used, &.{true}));
    defer assert(PluginState.plugins_count == PluginState.plugins_reloader.FileListCount);

    const alloc = CoreAllocator.allocator();
    std.fs.cwd().makePath("./annodue/tmp/plugin") catch
        @panic("failed to create temp plugin directory");

    PluginState.core = ArrayList(Plugin).init(alloc);

    var p: *Plugin = undefined;

    // loading core
    // TODO: hot-reloading core (i.e. all of annodue)

    // TODO: move to LoadPlugin equivalent?
    // TODO: (after hot-reloading core) run OnLateInit immediately on hot-reload like plugins
    // TODO: filtering/error-checking the fields to make sure they're actually objects, not functions etc.
    const fn_fields = comptime std.enums.values(PluginExportFn);
    const core_decls = comptime @typeInfo(core).Struct.decls;
    inline for (core_decls) |cd| {
        const decl = @field(core, cd.name);
        var this_p: ?*Plugin = null;
        inline for (fn_fields) |ff| {
            if (@hasDecl(decl, @tagName(ff))) {
                if (this_p == null) {
                    p = PluginState.core.addOne() catch @panic("failed to add core plugin to arraylist");
                    p.* = std.mem.zeroInit(Plugin, .{});
                    this_p = p;
                }
                @field(this_p.?, @tagName(ff)) = &@field(decl, @tagName(ff));

                comptime if (!@hasDecl(decl, "OnInit") or
                    !@hasDecl(decl, "OnInitLate") or
                    !@hasDecl(decl, "OnDeinit"))
                    dbg.PCompileError("'{s}' missing OnInit, OnInitLate or OnDeinit", .{cd.name});
            }
        }
        if (this_p) |plug| {
            plug.OwnerId = PluginState.owners_core;
            PluginState.owners_core += 1;
            PluginState.working_owner = plug.OwnerId;
            plug.OnInit.?(GLOBAL_FUNCTION);
            PluginFnOnPluginInit(.OnPluginInitA, PluginState.working_owner);
        }
    }

    // loading plugins

    PluginState.HotReloadPlugin.Init(&PluginState.plugins_reloader, PluginState.LoadPluginCallback);
    PluginState.plugins_reloader.fnLoadResult = PluginState.LoadPluginResultCallback;
    PluginState.plugins_reloader.CheckDelay = 40; // 25fps in ms
    PluginState.plugins_used = std.mem.zeroes([PluginState.PLUGIN_MAX]bool);
    PluginState.plugins_count = 0;
    defer PluginState.plugins_toast_count = 0;

    // TODO: check that each filename is short enough that both the plugin directory
    //  filepath and the temp file path lengths don't exceed MAX_PATH_SENTINEL
    // FIXME: assumes cwd is the game directory
    var d = std.fs.cwd().makeOpenPathIterable("./annodue/plugin", .{}) catch null;
    if (d) |*dir| {
        defer dir.close();

        var buf_path = std.mem.zeroes([MAX_PATH_SENTINEL:0]u8);
        var buf_ext: [4]u8 = undefined;

        var it_dir = dir.iterate();
        while (it_dir.next() catch null) |file| {
            if (file.kind != .file) continue;

            if (file.name.len < 4) continue; // minimum length for extension
            _ = std.ascii.lowerString(&buf_ext, file.name[file.name.len - 4 ..]);
            if (!std.mem.endsWith(u8, ".dll", &buf_ext)) continue;

            _ = std.fmt.bufPrintZ(&buf_path, "./annodue/plugin/{s}", .{file.name}) catch continue;

            const handle = PluginState.plugins_count;
            PluginState.plugins[handle] = std.mem.zeroInit(Plugin, .{});

            PluginState.plugins_used[handle] = true;
            PluginState.plugins_count += 1;
            if (!PluginState.plugins_reloader.TrackFile(&buf_path, handle)) {
                // only runs if the callback never got a chance to cleanup
                PluginState.plugins_used[handle] = false;
                PluginState.plugins_count -= 1;
            }
        }
    }

    // hooking game

    var off = GLOBAL_STATE.patch_offset;
    off = HookGameSetup(off);
    off = HookGameLoop(off);
    off = HookEngineUpdate(off);
    off = HookInputUpdate(off);
    off = HookTimerUpdate(off);
    off = HookInitRaceQuads(off);
    off = HookInitHangQuads(off);
    //off = HookGameEnd(off);
    off = HookTextRender(off);
    off = HookMenuDrawing(off);
    off = HookSceneBeginEnd(off);
    //off = HookLoadSprite(off);
    GLOBAL_STATE.patch_offset = off;
}

// HOOKS

pub fn OnInit(gf: *GlobalFn) callconv(.C) void {
    PluginState.h_s_hot_reload =
        gf.ASettingOccupy(SettingHandle.getNull(), "PLUGIN_HOT_RELOAD", .B, .{ .b = true }, &PluginState.s_hot_reload, null);
}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

pub fn GameLoopB(gf: *GlobalFn) callconv(.C) void {
    if (PluginState.s_hot_reload) {
        PluginState.plugins_reloader.Update(rti.TIMESTAMP.*);

        var buf_toast: [127:0]u8 = undefined;
        for (0..PluginState.plugins_toast_count) |i| {
            const handle = PluginState.plugins_toast[i];
            assert(PluginState.plugins_used[handle]);

            const p: *const Plugin = &PluginState.plugins[handle];
            _ = std.fmt.bufPrintZ(&buf_toast, "Plugin Loaded: {s}", .{p.PluginName.?()}) catch continue;
            _ = gf.ToastNew(&buf_toast, r.Text.ColorRGB.Green.rgba(0));
        }
        PluginState.plugins_toast_count = 0;
    }
}

// GAME SETUP

// last function call in successful setup path
fn HookGameSetup(memory: usize) usize {
    const addr: usize = 0x4240AD;
    const len: usize = 0x4240B7 - addr;
    const off_call: usize = 0x4240AF - addr;
    return hook.detour_call(memory, addr, off_call, len, null, PluginFnCallback(.OnInitLate));
}

// GAME LOOP

fn HookGameLoop(memory: usize) usize {
    return hook.intercept_call(
        memory,
        0x49CE2A,
        PluginFnCallback(.GameLoopB),
        PluginFnCallback(.GameLoopA),
    );
}

// ENGINE UPDATES

fn HookEngineUpdate(memory: usize) usize {
    var off: usize = memory;

    // fn_445980 case 1
    // physics updates, etc.
    off = hook.intercept_call(off, 0x445991, PluginFnCallback(.EarlyEngineUpdateB), null);
    off = hook.intercept_call(off, 0x445A00, null, PluginFnCallback(.EarlyEngineUpdateA));

    // fn_445980 case 2
    // text processing, etc. before the actual render
    off = hook.intercept_call(off, 0x445A10, PluginFnCallback(.LateEngineUpdateB), null);
    off = hook.intercept_call(off, 0x445A40, null, PluginFnCallback(.LateEngineUpdateA));

    // the function before CallAll0x14, at the start of the entity updates block
    // EngineUpdateStage20A is the equivalent for end of block
    off = hook.intercept_call(off, 0x4459D1, PluginFnCallback(.EngineEntityUpdateB), null);

    // entity system stages in EarlyEngineUpdate (CallAll0x14, etc.)
    // will only run when game is not paused
    off = hook.intercept_call(off, 0x4459D6, null, PluginFnCallback(.EngineUpdateStage14A));
    off = hook.intercept_call(off, 0x4459E0, null, PluginFnCallback(.EngineUpdateStage18A));
    off = hook.intercept_call(off, 0x4459E5, null, PluginFnCallback(.EngineUpdateStage1CA));
    off = hook.intercept_call(off, 0x4459EF, null, PluginFnCallback(.EngineUpdateStage20A));

    return off;
}

// GAME LOOP TIMER

fn HookTimerUpdate(memory: usize) usize {
    // fn_480540, in early engine update
    return hook.intercept_call(
        memory,
        0x4459AF,
        PluginFnCallback(.TimerUpdateB),
        PluginFnCallback(.TimerUpdateA),
    );
}

// INPUT READING

// NOTE: before early engine update in main loop; not the only calls to the
// hooked functions, but the main ones
fn HookInputUpdate(memory: usize) usize {
    var off = memory;
    off = hook.intercept_call( // fn_404DD0
        off,
        0x423592,
        PluginFnCallback(.InputUpdateB),
        PluginFnCallback(.InputUpdateA),
    );
    off = hook.intercept_call( // fn_485630
        off,
        0x404DD7,
        PluginFnCallback(.InputUpdateControlsB),
        PluginFnCallback(.InputUpdateControlsA),
    );
    off = hook.intercept_call( // fn_486170
        off,
        0x4856B3,
        PluginFnCallback(.InputUpdateKeyboardB),
        PluginFnCallback(.InputUpdateKeyboardA),
    );
    off = hook.intercept_call( // fn_486340
        off,
        0x4856C1,
        PluginFnCallback(.InputUpdateJoysticksB),
        PluginFnCallback(.InputUpdateJoysticksA),
    );
    off = hook.intercept_call( // fn_486710
        off,
        0x4856C6,
        PluginFnCallback(.InputUpdateMouseB),
        PluginFnCallback(.InputUpdateMouseA),
    );
    return off;
}

// 'HANG' SETUP

// NOTE: disabling before fn to match RaceQuads
fn HookInitHangQuads(memory: usize) usize {
    const addr: usize = 0x454DCF;
    const len: usize = 0x454DD8 - addr;
    const off_call: usize = 0x454DD0 - addr;
    return hook.detour_call(memory, addr, off_call, len, null, PluginFnCallback(.InitHangQuadsA));
}

// SPRITES

// FIXME: remove stub and integrate one-param hooks with PluginFnCallback
fn HookLoadSprite(memory: usize) usize {
    return hook.intercept_call_one_u32_param(memory, 0x446FB5, &PluginFnCallback1_stub);
}

// RACE SETUP

// FIXME: before fn crashes when hooked with any function contents; disabling for now
fn HookInitRaceQuads(memory: usize) usize {
    const addr: usize = 0x466D76;
    const len: usize = 0x466D81 - addr;
    const off_call: usize = 0x466D79 - addr;
    return hook.detour_call(memory, addr, off_call, len, null, PluginFnCallback(.InitRaceQuadsA));
}

// GAME END; executable closing

// FIXME: probably just switch to fn_4240D0 (GameShutdown), not sure if hook should
// be before or after the function contents (or both); might want to make available
// opportunity to intercept e.g. the final savedata write
// also look into doexit_49EA80, may be the last thing called regardless of exit path,
// will definitely come after GameShutdown though
// WARNING: in the current scheme, core deinit happens before plugin deinit, keep this
// hook location as a stage2 or core-only deinit and use above for arbitrary deinit?
fn HookGameEnd(memory: usize) usize {
    const exit1_off: usize = 0x49CE31;
    const exit2_off: usize = 0x49CE3D;
    const exit1_len: usize = exit2_off - exit1_off - 1; // excluding retn
    const exit2_len: usize = 0x49CE48 - exit2_off - 1; // excluding retn
    var offset: usize = memory;

    offset = hook.detour(offset, exit1_off, exit1_len, null, PluginFnCallback(.OnDeinit));
    offset = hook.detour(offset, exit2_off, exit2_len, null, PluginFnCallback(.OnDeinit));

    return offset;
}

// MENU DRAW CALLS in 'Hang' callback0x14

fn HookMenuDrawing(memory: usize) usize {
    var off: usize = memory;

    // see fn_457620 @ 0x45777F
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 1, PluginFnCallback(.MenuTitleScreenB));
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 3, PluginFnCallback(.MenuStartRaceB));
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 4, PluginFnCallback(.MenuJunkyardB));
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 5, PluginFnCallback(.MenuRaceResultsB));
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 7, PluginFnCallback(.MenuWattosShopB));
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 8, PluginFnCallback(.MenuHangarB));
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 9, PluginFnCallback(.MenuVehicleSelectB));
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 12, PluginFnCallback(.MenuTrackSelectB));
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 13, PluginFnCallback(.MenuTrackB));
    off = hook.intercept_jumptable(off, reh.DRAW_MENU_JUMPTABLE_ADDR, 18, PluginFnCallback(.MenuCantinaEntryB));

    return off;
}

// TEXT RENDER QUEUE FLUSHING

fn HookTextRender(memory: usize) usize {
    // NOTE: 0x483F8B calls ProcessQueue1, only usable with after-fn when using intercept_call()
    var off = memory;
    // FlushQueue1
    // TODO: deprecate, update to be more reflective of current knowledge and add granularity
    off = hook.intercept_call(
        off,
        0x450297,
        PluginFnCallback(.TextRenderB),
        PluginFnCallback(.TextRenderA),
    );
    // FlushMapQueue
    off = hook.intercept_call(
        off,
        0x45029C,
        PluginFnCallback(.MapRenderB),
        PluginFnCallback(.MapRenderA),
    );
    // MetaCam_Draw2D
    off = hook.intercept_call(
        off,
        0x445A1A,
        PluginFnCallback(.Draw2DB),
        PluginFnCallback(.Draw2DA),
    );
    return off;
}

fn HookSceneBeginEnd(memory: usize) usize {
    var off = memory;

    // 3D_StartScene__48A300 in Render_Flush__48DCE0
    off = hook.intercept_call(
        off,
        0x48DCEC,
        PluginFnCallback(.RenderSceneBeginB),
        PluginFnCallback(.RenderSceneBeginA),
    );

    // 3D_EndScene__48A330 in Render_Flush__48DCE0
    off = hook.intercept_call(
        off,
        0x48DD5A,
        PluginFnCallback(.RenderSceneEndB),
        PluginFnCallback(.RenderSceneEndA),
    );

    return off;
}
