const Self = @This();

const BuildOptions = @import("BuildOptions");

const std = @import("std");
const SemVer = std.SemanticVersion;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
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
const GLOBAL_STATE = &core.Global.GLOBAL_STATE;
const GLOBAL_FUNCTION = &core.Global.GLOBAL_FUNCTION;

const app = @import("../appinfo.zig");
const GlobalFn = app.GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = app.COMPATIBILITY_VERSION;

const hot_reload = @import("../util/hot_reload.zig");
const hook = @import("../util/hooking.zig");
const apih = @import("../util/api/api_helper.zig");
const debug = @import("../util/debug/debug.zig");

const MiB = @import("../util/base/base_memory.zig").MiB;

const SettingHandle = @import("ASettings.zig").Handle;
const SettingValue = @import("ASettings.zig").ASettingSent.Value;
const Setting = @import("ASettings.zig").ASettingSent;

// FIXME: anything using this should be moved to api Init; waiting on better core arch
const RAddress = @import("RAddress.zig");
const RAddressHandle = @import("../util/api/api.zig").RAddressHandle;
const RADDRESS_HANDLE_NULL = @import("../util/api/api.zig").RADDRESS_HANDLE_NULL;

const r = @import("racer");
const reh = r.Entity.Hang;
const rti = r.Time;

// TODO: switch to Sha256 for perf?
const Sha512 = std.crypto.hash.sha2.Sha512;
const plugin_hashes_data = @embedFile("hashfile");
const plugin_hashes_len: u32 = (plugin_hashes_data.len - 4) / 64;
const plugin_hashes: *align(1) const [plugin_hashes_len][64]u8 = std.mem.bytesAsValue([plugin_hashes_len][64]u8, plugin_hashes_data[4..]);

// NOTE: currently, "early init" happens at 0x48540B (call DirectInputCreateA);
//  this is planned to change to top of WinMain with new dinput hooking method
// TODO: change "global function" nomenclature to "API function" project-wide

// TODO: pull out plugin-related defs to separate module, so that it can be
//  used as part of libannodue, and thus be importable by independent plugin
//  projects. i.e. the cutoff point should be where it makes the most sense
//  to separate plugin "metadata" from the stuff integrating them as hooks
//    random ideas
//    - make Plugin somewhat parameterized wrt which exported symbols it actually
//      looks for, which ones are associated with which function signatures, which
//      ones are actually required/rejected by core and user-plugin, etc.. probably
//      do some kind of comptime input array that gets translated into various ref
//      arrays thing, a la hashimoto "comptime data tables"
//         - benefit: readability via helper functions on the metadata check in LoadPluginCallback
//         - benefit: less definitions for various usecases spread out across file

// FIXME: hooking (settings?) deinit causes racer process to never end, but only
// when you quit with the X button, not with the ingame quit option
// that said, again probably pointless to bother manually deallocating at the end anyway

// OKOKOKOKOK

pub const PLUGIN_FUNCTION_VERSION = 1;

const Plugin = plugin: {
    const stdf = .{
        .{ "Handle", ?HINSTANCE },
        .{ "Initialized", bool },
        .{ "OwnerId", Owner },
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
        .OnPluginInitA, .OnPluginInitLateA, .OnPluginDeinitA => ?*const fn (OwnerOpaque) callconv(.C) void,
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

pub const OwnerOpaque = u16;

pub const Owner = packed struct(u16) {
    Kind: OwnerKind,
    Id: u14,

    pub const OwnerKind = enum(u2) { None = 0, Core = 1, User = 2 };
    pub const NULL = Owner{ .Kind = .None, .Id = 0 };
    pub const NULL_CORE = Owner{ .Kind = .Core, .Id = 0 };
    pub const NULL_USER = Owner{ .Kind = .User, .Id = 0 };

    pub fn Init(kind: OwnerKind, id: u14) Owner {
        return Owner{ .Kind = kind, .Id = id };
    }

    pub fn Eql(self: Owner, other: Owner) bool {
        return self.Opaque() == other.Opaque();
    }

    pub fn Opaque(self: Owner) OwnerOpaque {
        return @bitCast(self);
    }

    pub fn FromOpaque(other: OwnerOpaque) Owner {
        return @bitCast(other);
    }
};

// TODO: directory-monitoring hot_reload impl (need for core menu impl)
// TODO: review plugin-related loops (including hot_reload impl); probably not
//  a performance concern at all given the current array sizes, but there is
//  a lot of looping over "nothing" when calling plugin functions and this grows
//  at N*M for every plugin and callback hook added
// TODO: owner range limiting
pub const PluginState = struct {
    var arena_perm: Allocator = undefined;
    var arena_temp: Allocator = undefined;

    var h_s_hot_reload: ?SettingHandle = null;
    var s_hot_reload: bool = true;

    var core: ArrayList(Plugin) = undefined;
    var core_fba: FixedBufferAllocator = undefined;

    const PLUGIN_MAX = 64;
    const HotReloadPluginHandle = u32;
    const HotReloadPlugin = hot_reload.HotReload(HotReloadPluginHandle, PLUGIN_MAX);
    var plugins: [PLUGIN_MAX]Plugin = undefined;
    var plugins_used: [PLUGIN_MAX]bool = std.mem.zeroes([PLUGIN_MAX]bool);
    var plugins_count: u32 = 0;
    var plugins_toast: [PLUGIN_MAX]HotReloadPluginHandle = undefined;
    var plugins_toast_count: u32 = 0;
    var plugins_reloader: HotReloadPlugin = undefined;

    var owner_count_core: u14 = 0;
    var owner_count_user: u14 = 0;
    // FIXME: this could be ref'd outside of callback/work context, in which case
    //  it will contain the most recent context's owner, not the owner of whoever
    //  is making the ref
    var owner_current: Owner = Owner.NULL;

    // TODO: some kind of tracking in the ownership system that asserts there is
    //  actually a plugin/module being worked on when the working owner is accessed.
    //  for now accepting plain NULL owner as compromise, since a full solution
    //  likely requires reworking handle_map (and anything depending on it)
    pub fn WorkingOwner() OwnerOpaque {
        assert(!owner_current.Eql(Owner.NULL_CORE));
        assert(!owner_current.Eql(Owner.NULL_USER));
        return owner_current.Opaque();
    }

    // TODO: more robust/direct check
    pub fn WorkingOwnerIsSystem() bool {
        return Owner.FromOpaque(WorkingOwner()).Kind != .User;
    }

    /// callback for Plugin hot_reload impl; the file given is assumed to be newer
    fn UnloadPluginCallback(handle: HotReloadPluginHandle, _: [:0]const u8, _: [:0]const u8) void {
        assert(handle < PLUGIN_MAX);
        assert(plugins_used[handle]);

        const p: *Plugin = &plugins[handle];
        if (!p.Initialized) return; // already unloaded

        if (p.Handle) |h| {
            p.OnDeinit.?(GLOBAL_FUNCTION);
            PluginFnOnPluginInit(.OnPluginDeinitA, p.OwnerId);
            _ = FreeLibrary(h);
            p.Initialized = false;
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
        assert(plugins_used[handle]);
        assert(!plugins[handle].Initialized);
        var result: bool = false;

        defer {
            assert(plugins_used[handle]);
            assert(plugins[handle].Initialized == result);
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

        const p: *Plugin = &plugins[handle];

        // FIXME: to remove; will be embedding stock plugins moving forward
        if (BuildOptions.BUILD_MODE != .Developer) blk: {
            const this_hash = getFileSha512(filepath) catch return result;
            for (plugin_hashes) |hash|
                if (std.mem.eql(u8, &this_hash, &hash))
                    break :blk;
            return result;
        }

        var buf_tmp = PluginState.arena_temp.create([MAX_PATH_SENTINEL:0]u8) catch return result;
        const filename_no_ext = filename[0 .. filename.len - 4];
        _ = std.fmt.bufPrintZ(buf_tmp, "./annodue/tmp/plugin/{s}.tmp.dll", .{filename_no_ext}) catch
            return result;

        // now we ball

        _ = CopyFileA(filepath, buf_tmp, 0);
        p.Handle = LoadLibraryA(buf_tmp);
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
            return result;
        }

        PluginState.owner_count_user += 1;
        PluginState.owner_current = Owner.Init(.User, PluginState.owner_count_user);
        p.OwnerId = PluginState.owner_current;
        p.OnInit.?(GLOBAL_FUNCTION);
        PluginFnOnPluginInit(.OnPluginInitA, p.OwnerId);
        if (GLOBAL_STATE.init_late_passed) p.OnInitLate.?(GLOBAL_FUNCTION);
        p.Initialized = true;

        result = true;
        return result;
    }
};

pub fn PluginFnCallback(comptime ex: PluginExportFn) *const fn () void {
    const c = struct {
        fn callback() void {
            for (PluginState.core.items) |p| {
                PluginState.owner_current = p.OwnerId;
                if (@field(p, @tagName(ex))) |f| {
                    f(GLOBAL_FUNCTION);
                    switch (ex) {
                        .OnInitLate => PluginFnOnPluginInit(.OnPluginInitLateA, p.OwnerId),
                        else => {},
                    }
                }
            }
            for (PluginState.plugins_used, 0..) |used, i| {
                if (!used) continue;
                const p: *const Plugin = &PluginState.plugins[i];
                PluginState.owner_current = p.OwnerId;
                if (@field(p, @tagName(ex))) |f| {
                    f(GLOBAL_FUNCTION);
                    switch (ex) {
                        .OnInitLate => PluginFnOnPluginInit(.OnPluginInitLateA, p.OwnerId),
                        else => {},
                    }
                }
            }
        }
    };
    return &c.callback;
}

/// callback for core modules to run when any module is init/deinit, so that core
/// features can do automatic processing of resources accessed via the plugin api
/// and not rely on modules being good citizens. this function is run after the
/// module's own init/deinit are run
/// @owner  the plugin actually being init/deinit that this function is called in reaction to
pub fn PluginFnOnPluginInit(comptime ex: PluginExportFn, owner: Owner) void {
    comptime if (ex != .OnPluginInitA and
        ex != .OnPluginInitLateA and
        ex != .OnPluginDeinitA) @compileError("invalid plugin export fn");

    for (PluginState.core.items) |p| {
        if (p.OwnerId.Eql(owner)) continue; // skip running own init/deinit callback
        PluginState.owner_current = p.OwnerId;
        if (@field(p, @tagName(ex))) |f| f(owner.Opaque());
    }
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

const CORE_BUFFER_SIZE = MiB(u32, 4);

const PATCH_BUFFER_SIZE = MiB(u32, 4);
var patch_buf: []u8 = &.{};
var patch_off: u32 = 0;

// NOTE: all reserved addresses in one spot for visibility
var h_ar_GameSetup: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_GameLoop: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_EngineUpdate1: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_EngineUpdate2: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_EngineUpdate3: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_EngineUpdate4: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_EngineUpdate5: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_EngineUpdate6: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_EngineUpdate7: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_EngineUpdate8: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_EngineUpdate9: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_InputUpdate1: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_InputUpdate2: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_InputUpdate3: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_InputUpdate4: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_InputUpdate5: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_TimerUpdate: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_InitRaceQuads: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_InitHangQuads: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_GameEnd1: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_GameEnd2: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_TextRender1: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_TextRender2: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_TextRender3: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_MenuDrawing: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_SceneBeginEnd1: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_SceneBeginEnd2: RAddressHandle = RADDRESS_HANDLE_NULL;
var h_ar_LoadSprite: RAddressHandle = RADDRESS_HANDLE_NULL;

pub fn init(arena_perm: Allocator, arena_temp: Allocator) !void {
    defer assert(PluginState.plugins_count == std.mem.count(bool, &PluginState.plugins_used, &.{true}));
    defer assert(PluginState.plugins_count == PluginState.plugins_reloader.FileListCount);

    // hooking game

    patch_buf = try arena_perm.create([PATCH_BUFFER_SIZE]u8);
    patch_off = @intFromPtr(patch_buf.ptr);
    defer assert(patch_off <= @intFromPtr(patch_buf.ptr) + patch_buf.len);

    patch_off = HookGameSetup(patch_off);
    patch_off = HookGameLoop(patch_off);
    patch_off = HookEngineUpdate(patch_off);
    patch_off = HookInputUpdate(patch_off);
    patch_off = HookTimerUpdate(patch_off);
    patch_off = HookInitRaceQuads(patch_off);
    patch_off = HookInitHangQuads(patch_off);
    //patch_off = HookGameEnd(patch_off);
    patch_off = HookTextRender(patch_off);
    patch_off = HookMenuDrawing(patch_off);
    patch_off = HookSceneBeginEnd(patch_off);
    //patch_off = HookLoadSprite(patch_off);

    // loading modules

    PluginState.arena_perm = arena_perm;
    PluginState.arena_temp = arena_temp;

    try std.fs.cwd().makePath("./annodue/tmp/plugin");

    // FIXME: core_fba probably not necessary? need to generally rethink memory
    //  here and for plugins anyway
    var core_mem = try arena_perm.create([CORE_BUFFER_SIZE]u8);
    PluginState.core_fba = FixedBufferAllocator.init(core_mem);
    PluginState.core = ArrayList(Plugin).init(PluginState.core_fba.allocator());

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
                    p = PluginState.core.addOne() catch |e|
                        std.debug.panic("AHook(Init): {s}(CoreArray)", .{@errorName(e)});
                    p.* = std.mem.zeroInit(Plugin, .{});
                    this_p = p;
                }
                @field(this_p.?, @tagName(ff)) = &@field(decl, @tagName(ff));

                comptime if (!@hasDecl(decl, "OnInit") or
                    !@hasDecl(decl, "OnInitLate") or
                    !@hasDecl(decl, "OnDeinit"))
                    debug.PCompileError("'{s}' missing OnInit, OnInitLate or OnDeinit", .{cd.name});
            }
        }
        if (this_p) |plug| {
            PluginState.owner_count_core += 1;
            PluginState.owner_current = Owner.Init(.Core, PluginState.owner_count_core);
            plug.OwnerId = PluginState.owner_current;
            plug.OnInit.?(GLOBAL_FUNCTION);
            PluginFnOnPluginInit(.OnPluginInitA, plug.OwnerId);
        }
    }

    // loading plugins

    PluginState.plugins_reloader.Init(PluginState.LoadPluginCallback, PluginState.UnloadPluginCallback);
    PluginState.plugins_reloader.CheckDelay = 40; // 25fps in ms
    PluginState.plugins_used = std.mem.zeroes([PluginState.PLUGIN_MAX]bool);
    PluginState.plugins_count = 0;
    defer PluginState.plugins_toast_count = 0; // don't toast initial plugin load

    // TODO: check that each filename is short enough that both the plugin directory
    //  filepath and the temp file path lengths don't exceed MAX_PATH_SENTINEL
    // FIXME: assumes cwd is the game directory
    var d = std.fs.cwd().makeOpenPathIterable("./annodue/plugin", .{}) catch null;
    if (d) |*dir| {
        defer assert(PluginState.plugins_count == PluginState.plugins_reloader.FileListCount);
        defer assert(PluginState.plugins_count <= PluginState.PLUGIN_MAX);
        defer dir.close();

        var buf_path = try arena_temp.create([MAX_PATH_SENTINEL:0]u8);
        var buf_ext = try arena_temp.create([4]u8);

        var it_dir = dir.iterate();
        while (it_dir.next() catch null) |file| {
            if (PluginState.plugins_count == PluginState.PLUGIN_MAX) break;
            if (file.kind != .file) continue;

            if (file.name.len < 4) continue; // minimum length for extension
            _ = std.ascii.lowerString(buf_ext, file.name[file.name.len - 4 ..]);
            if (!std.mem.endsWith(u8, ".dll", buf_ext)) continue;

            _ = std.fmt.bufPrintZ(buf_path, "./annodue/plugin/{s}", .{file.name}) catch continue;

            const handle = PluginState.plugins_count;
            PluginState.plugins[handle] = std.mem.zeroInit(Plugin, .{});

            PluginState.plugins_used[handle] = true;
            PluginState.plugins_count += 1;
            _ = PluginState.plugins_reloader.TrackFile(buf_path, handle);
        }
    }
}

// HOOKS

pub fn OnInit(gf: *GlobalFn) callconv(.C) void {
    PluginState.h_s_hot_reload =
        gf.ASettingOccupy(SettingHandle.getNull(), "PLUGIN_HOT_RELOAD", .B, .{ .b = true }, &PluginState.s_hot_reload, null);
}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {}

pub fn GameLoopB(gf: *GlobalFn) callconv(.C) void {
    if (PluginState.s_hot_reload) blk: {
        PluginState.plugins_reloader.Update(rti.TIMESTAMP.*);

        defer PluginState.plugins_toast_count = 0;
        var buf_toast = apih.AMemoryGetTemporaryZeroT(gf, [127:0]u8) orelse break :blk;
        for (0..PluginState.plugins_toast_count) |i| {
            const handle = PluginState.plugins_toast[i];
            assert(PluginState.plugins_used[handle]);

            const p: *const Plugin = &PluginState.plugins[handle];
            _ = std.fmt.bufPrintZ(buf_toast, "Plugin Loaded: {s}", .{p.PluginName.?()}) catch continue;
            _ = gf.ToastNew(buf_toast, r.Text.ColorRGB.Green.rgba(0));
        }
    }
}

// GAME SETUP

// last function call in successful setup path
fn HookGameSetup(memory: usize) usize {
    h_ar_GameSetup = RAddress.RAddressRangeReserve(0x4240AD, 0x4240B7);
    if (!RAddress.RAddressRangeWriteSt(h_ar_GameSetup)) @panic("HookGameSetup: RAddressRangeWriteSt failed");
    defer RAddress.RAddressRangeWriteEd(h_ar_GameSetup);

    const addr: usize = 0x4240AD;
    const len: usize = 0x4240B7 - addr;
    const off_call: usize = 0x4240AF - addr;
    return hook.detour_call(memory, addr, off_call, len, null, PluginFnCallback(.OnInitLate));
}

// GAME LOOP

fn HookGameLoop(memory: usize) usize {
    h_ar_GameLoop = RAddress.RAddressRangeReserve(0x49CE2A, 0x49CE2F);
    if (!RAddress.RAddressRangeWriteSt(h_ar_GameLoop)) @panic("HookGameLoop: RAddressRangeWriteSt failed");
    defer RAddress.RAddressRangeWriteEd(h_ar_GameLoop);

    return hook.intercept_call(
        memory,
        0x49CE2A,
        PluginFnCallback(.GameLoopB),
        PluginFnCallback(.GameLoopA),
    );
}

// ENGINE UPDATES

fn HookEngineUpdate(memory: usize) usize {
    h_ar_EngineUpdate1 = RAddress.RAddressRangeReserve(0x445991, 0x445991 + 5);
    h_ar_EngineUpdate2 = RAddress.RAddressRangeReserve(0x445A00, 0x445A00 + 5);
    h_ar_EngineUpdate3 = RAddress.RAddressRangeReserve(0x445A10, 0x445A10 + 5);
    h_ar_EngineUpdate4 = RAddress.RAddressRangeReserve(0x445A40, 0x445A40 + 5);
    h_ar_EngineUpdate5 = RAddress.RAddressRangeReserve(0x4459D1, 0x4459D1 + 5);
    h_ar_EngineUpdate6 = RAddress.RAddressRangeReserve(0x4459D6, 0x4459D6 + 5);
    h_ar_EngineUpdate7 = RAddress.RAddressRangeReserve(0x4459E0, 0x4459E0 + 5);
    h_ar_EngineUpdate8 = RAddress.RAddressRangeReserve(0x4459E5, 0x4459E5 + 5);
    h_ar_EngineUpdate9 = RAddress.RAddressRangeReserve(0x4459EF, 0x4459EF + 5);

    var off: usize = memory;

    // fn_445980 case 1
    // physics updates, etc.
    if (RAddress.RAddressRangeWriteSt(h_ar_EngineUpdate1)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_EngineUpdate1);
        off = hook.intercept_call(off, 0x445991, PluginFnCallback(.EarlyEngineUpdateB), null);
    } else @panic("HookEngineUpdate: RAddressRangeWriteSt failed (EarlyEngineUpdateB)");
    if (RAddress.RAddressRangeWriteSt(h_ar_EngineUpdate2)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_EngineUpdate2);
        off = hook.intercept_call(off, 0x445A00, null, PluginFnCallback(.EarlyEngineUpdateA));
    } else @panic("HookEngineUpdate: RAddressRangeWriteSt failed (EarlyEngineUpdateA)");

    // fn_445980 case 2
    // text processing, etc. before the actual render
    if (RAddress.RAddressRangeWriteSt(h_ar_EngineUpdate3)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_EngineUpdate3);
        off = hook.intercept_call(off, 0x445A10, PluginFnCallback(.LateEngineUpdateB), null);
    } else @panic("HookEngineUpdate: RAddressRangeWriteSt failed (LateEngineUpdateB)");
    if (RAddress.RAddressRangeWriteSt(h_ar_EngineUpdate4)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_EngineUpdate4);
        off = hook.intercept_call(off, 0x445A40, null, PluginFnCallback(.LateEngineUpdateA));
    } else @panic("HookEngineUpdate: RAddressRangeWriteSt failed (LateEngineUpdateA)");

    // the function before CallAll0x14, at the start of the entity updates block
    // EngineUpdateStage20A is the equivalent for end of block
    if (RAddress.RAddressRangeWriteSt(h_ar_EngineUpdate5)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_EngineUpdate5);
        off = hook.intercept_call(off, 0x4459D1, PluginFnCallback(.EngineEntityUpdateB), null);
    } else @panic("HookEngineUpdate: RAddressRangeWriteSt failed (EngineEntityUpdateB)");

    // entity system stages in EarlyEngineUpdate (CallAll0x14, etc.)
    // will only run when game is not paused
    if (RAddress.RAddressRangeWriteSt(h_ar_EngineUpdate6)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_EngineUpdate6);
        off = hook.intercept_call(off, 0x4459D6, null, PluginFnCallback(.EngineUpdateStage14A));
    } else @panic("HookEngineUpdate: RAddressRangeWriteSt failed (EngineUpdateStage14A)");
    if (RAddress.RAddressRangeWriteSt(h_ar_EngineUpdate7)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_EngineUpdate7);
        off = hook.intercept_call(off, 0x4459E0, null, PluginFnCallback(.EngineUpdateStage18A));
    } else @panic("HookEngineUpdate: RAddressRangeWriteSt failed (EngineUpdateStage18A)");
    if (RAddress.RAddressRangeWriteSt(h_ar_EngineUpdate8)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_EngineUpdate8);
        off = hook.intercept_call(off, 0x4459E5, null, PluginFnCallback(.EngineUpdateStage1CA));
    } else @panic("HookEngineUpdate: RAddressRangeWriteSt failed (EngineUpdateStage1CA)");
    if (RAddress.RAddressRangeWriteSt(h_ar_EngineUpdate9)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_EngineUpdate9);
        off = hook.intercept_call(off, 0x4459EF, null, PluginFnCallback(.EngineUpdateStage20A));
    } else @panic("HookEngineUpdate: RAddressRangeWriteSt failed (EngineUpdateStage20A)");

    return off;
}

// GAME LOOP TIMER

fn HookTimerUpdate(memory: usize) usize {
    h_ar_TimerUpdate = RAddress.RAddressRangeReserve(0x4459AF, 0x4459AF + 5);
    if (!RAddress.RAddressRangeWriteSt(h_ar_TimerUpdate)) @panic("HookTimerUpdate: RAddressRangeWriteSt failed");
    defer RAddress.RAddressRangeWriteEd(h_ar_TimerUpdate);

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
    h_ar_InputUpdate1 = RAddress.RAddressRangeReserve(0x423592, 0x423592 + 5);
    h_ar_InputUpdate2 = RAddress.RAddressRangeReserve(0x404DD7, 0x404DD7 + 5);
    h_ar_InputUpdate3 = RAddress.RAddressRangeReserve(0x4856B3, 0x4856B3 + 5);
    h_ar_InputUpdate4 = RAddress.RAddressRangeReserve(0x4856C1, 0x4856C1 + 5);
    h_ar_InputUpdate5 = RAddress.RAddressRangeReserve(0x4856C6, 0x4856C6 + 5);

    var off = memory;
    if (RAddress.RAddressRangeWriteSt(h_ar_InputUpdate1)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_InputUpdate1);
        off = hook.intercept_call( // fn_404DD0
            off,
            0x423592,
            PluginFnCallback(.InputUpdateB),
            PluginFnCallback(.InputUpdateA),
        );
    } else @panic("HookInputUpdate: RAddressRangeWriteSt failed (InputUpdate)");
    if (RAddress.RAddressRangeWriteSt(h_ar_InputUpdate2)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_InputUpdate2);
        off = hook.intercept_call( // fn_485630
            off,
            0x404DD7,
            PluginFnCallback(.InputUpdateControlsB),
            PluginFnCallback(.InputUpdateControlsA),
        );
    } else @panic("HookInputUpdate: RAddressRangeWriteSt failed (InputUpdateControls)");
    if (RAddress.RAddressRangeWriteSt(h_ar_InputUpdate3)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_InputUpdate3);
        off = hook.intercept_call( // fn_486170
            off,
            0x4856B3,
            PluginFnCallback(.InputUpdateKeyboardB),
            PluginFnCallback(.InputUpdateKeyboardA),
        );
    } else @panic("HookInputUpdate: RAddressRangeWriteSt failed (InputUpdateKeyboard)");
    if (RAddress.RAddressRangeWriteSt(h_ar_InputUpdate4)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_InputUpdate4);
        off = hook.intercept_call( // fn_486340
            off,
            0x4856C1,
            PluginFnCallback(.InputUpdateJoysticksB),
            PluginFnCallback(.InputUpdateJoysticksA),
        );
    } else @panic("HookInputUpdate: RAddressRangeWriteSt failed (InputUpdateJoysticks)");
    if (RAddress.RAddressRangeWriteSt(h_ar_InputUpdate5)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_InputUpdate5);
        off = hook.intercept_call( // fn_486710
            off,
            0x4856C6,
            PluginFnCallback(.InputUpdateMouseB),
            PluginFnCallback(.InputUpdateMouseA),
        );
    } else @panic("HookInputUpdate: RAddressRangeWriteSt failed (InputUpdateMouse)");
    return off;
}

// 'HANG' SETUP

// NOTE: disabling before fn to match RaceQuads
fn HookInitHangQuads(memory: usize) usize {
    h_ar_InitHangQuads = RAddress.RAddressRangeReserve(0x454DCF, 0x454DD8);
    if (!RAddress.RAddressRangeWriteSt(h_ar_InitHangQuads)) @panic("HookInitHangQuads: RAddressRangeWriteSt failed");
    defer RAddress.RAddressRangeWriteEd(h_ar_InitHangQuads);

    const addr: usize = 0x454DCF;
    const len: usize = 0x454DD8 - addr;
    const off_call: usize = 0x454DD0 - addr;
    return hook.detour_call(memory, addr, off_call, len, null, PluginFnCallback(.InitHangQuadsA));
}

// SPRITES

// FIXME: remove stub and integrate one-param hooks with PluginFnCallback
fn HookLoadSprite(memory: usize) usize {
    h_ar_LoadSprite = RAddress.RAddressRangeReserve(0x446FB5, 0x446FB5 + 5);
    if (!RAddress.RAddressRangeWriteSt(h_ar_LoadSprite)) @panic("HookLoadSprite: RAddressRangeWriteSt failed");
    defer RAddress.RAddressRangeWriteEd(h_ar_LoadSprite);

    return hook.intercept_call_one_u32_param(memory, 0x446FB5, &PluginFnCallback1_stub);
}

// RACE SETUP

// FIXME: before fn crashes when hooked with any function contents; disabling for now
fn HookInitRaceQuads(memory: usize) usize {
    h_ar_InitRaceQuads = RAddress.RAddressRangeReserve(0x466D76, 0x466D81);
    if (!RAddress.RAddressRangeWriteSt(h_ar_InitRaceQuads)) @panic("HookInitRaceQuads: RAddressRangeWriteSt failed");
    defer RAddress.RAddressRangeWriteEd(h_ar_InitRaceQuads);

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

    h_ar_GameEnd1 = RAddress.RAddressRangeReserve(exit1_off, exit1_off + exit1_len);
    h_ar_GameEnd2 = RAddress.RAddressRangeReserve(exit2_off, exit2_off + exit2_len);

    var offset: usize = memory;

    if (RAddress.RAddressRangeWriteSt(h_ar_GameEnd1)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_GameEnd1);
        offset = hook.detour(offset, exit1_off, exit1_len, null, PluginFnCallback(.OnDeinit));
    } else @panic("HookGameEnd: RAddressRangeWriteSt failed (exit1)");
    if (RAddress.RAddressRangeWriteSt(h_ar_GameEnd2)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_GameEnd2);
        offset = hook.detour(offset, exit2_off, exit2_len, null, PluginFnCallback(.OnDeinit));
    } else @panic("HookGameEnd: RAddressRangeWriteSt failed (exit2)");

    return offset;
}

// MENU DRAW CALLS in 'Hang' callback0x14

fn HookMenuDrawing(memory: usize) usize {
    // TODO: add jumptable end to reh (or length, or full typedef)
    h_ar_MenuDrawing = RAddress.RAddressRangeReserve(reh.DRAW_MENU_JUMPTABLE_ADDR, 0x457AD4);
    if (!RAddress.RAddressRangeWriteSt(h_ar_MenuDrawing)) @panic("HookMenuDrawing: RAddressRangeWriteSt failed");
    defer RAddress.RAddressRangeWriteEd(h_ar_MenuDrawing);

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
    h_ar_TextRender1 = RAddress.RAddressRangeReserve(0x450297, 0x450297 + 5);
    h_ar_TextRender2 = RAddress.RAddressRangeReserve(0x45029C, 0x45029C + 5);
    h_ar_TextRender3 = RAddress.RAddressRangeReserve(0x445A1A, 0x445A1A + 5);

    // NOTE: 0x483F8B calls ProcessQueue1, only usable with after-fn when using intercept_call()
    var off = memory;
    // FlushQueue1
    // TODO: deprecate, update to be more reflective of current knowledge and add granularity
    if (RAddress.RAddressRangeWriteSt(h_ar_TextRender1)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_TextRender1);
        off = hook.intercept_call(
            off,
            0x450297,
            PluginFnCallback(.TextRenderB),
            PluginFnCallback(.TextRenderA),
        );
    } else @panic("HookTextRender: RAddressRangeWriteSt failed (FlushQueue1)");
    // FlushMapQueue
    if (RAddress.RAddressRangeWriteSt(h_ar_TextRender2)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_TextRender2);
        off = hook.intercept_call(
            off,
            0x45029C,
            PluginFnCallback(.MapRenderB),
            PluginFnCallback(.MapRenderA),
        );
    } else @panic("HookTextRender: RAddressRangeWriteSt failed (FlushMapQueue)");
    // MetaCam_Draw2D
    if (RAddress.RAddressRangeWriteSt(h_ar_TextRender3)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_TextRender3);
        off = hook.intercept_call(
            off,
            0x445A1A,
            PluginFnCallback(.Draw2DB),
            PluginFnCallback(.Draw2DA),
        );
    } else @panic("HookTextRender: RAddressRangeWriteSt failed (Viewport_Draw2D)");
    return off;
}

fn HookSceneBeginEnd(memory: usize) usize {
    h_ar_SceneBeginEnd1 = RAddress.RAddressRangeReserve(0x48DCEC, 0x48DCEC + 5);
    h_ar_SceneBeginEnd2 = RAddress.RAddressRangeReserve(0x48DD5A, 0x48DD5A + 5);

    var off = memory;

    // 3D_StartScene__48A300 in Render_Flush__48DCE0
    if (RAddress.RAddressRangeWriteSt(h_ar_SceneBeginEnd1)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_SceneBeginEnd1);
        off = hook.intercept_call(
            off,
            0x48DCEC,
            PluginFnCallback(.RenderSceneBeginB),
            PluginFnCallback(.RenderSceneBeginA),
        );
    } else @panic("HookSceneBeginEnd: RAddressRangeWriteSt failed (StartScene)");

    // 3D_EndScene__48A330 in Render_Flush__48DCE0
    if (RAddress.RAddressRangeWriteSt(h_ar_SceneBeginEnd2)) {
        defer RAddress.RAddressRangeWriteEd(h_ar_SceneBeginEnd2);
        off = hook.intercept_call(
            off,
            0x48DD5A,
            PluginFnCallback(.RenderSceneEndB),
            PluginFnCallback(.RenderSceneEndA),
        );
    } else @panic("HookSceneBeginEnd: RAddressRangeWriteSt failed (EndScene)");

    return off;
}
