const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const msg = @import("util/message.zig");

// FIXME: remove or whatever, testing
var gpa: GeneralPurposeAllocator(.{}) = GeneralPurposeAllocator(.{}){};
const Handle = @import("util/handle_map.zig").Handle;
const HandleMap = @import("util/handle_map.zig").HandleMap;
const HandleStatic = @import("util/handle_map_static.zig").Handle;
const HandleMapStatic = @import("util/handle_map_static.zig").HandleMapStatic;
const x86 = @import("util/x86.zig");
const mem = @import("util/memory.zig");
const BOOL = std.os.windows.BOOL;
const r = @import("racer");
const Test = r.Entity.Test.Test;
const Test_HandleTerrain = r.Entity.Test.HandleTerrain;
const Trig = r.Entity.Trig.Trig;
const Trig_HandleTriggers = r.Entity.Trig.HandleTriggers;
const t = r.Text;
const mo = r.Model;
const ModelMesh_GetBehavior = mo.Mesh_GetBehavior;
const TriggerDescription_AddItem = mo.TriggerDescription_AddItem;
const ModelMesh = mo.ModelMesh;
const ModelBehavior = mo.ModelBehavior;
const ModelTriggerDescription = mo.ModelTriggerDescription;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// -
// - CONTROLS:      keyboard        xinput
//   ..             ..              ..
// - SETTINGS:
//   ..             type    note

// TRIGGERS

// TODO: explain lifecycle of a trigger common model-entity interactions at each stage, ..
// notes for plugin devs:
// - you have to do any modelblock-related init and cleanup yourself
// - you may want to call Trig_CreateTrigger during fnDoInit to 'pre-seed' a Trig entity
// - entity-related auto-cleanup behaviour depends on what callbacks you define
//   - neither fnDoEntityDestroy OR fnDoEntityUpdate = trigger cleared immediately
//   - fnDoEntityDestroy = trigger cleared at your discretion
//   - only fnDoEntityUpdate = trigger never cleared
// - use bits 6..15 in model trigger description flags as arbitrary "settings" data
//   - accessible via 'settings' args in callbacks
//   - shifted down to bits 0..9, with bits 10..15 zeroed out
//   - use it however you like, as bitfield, packed struct, int/float, etc.

const TRIGGER_LIMIT_GAME: usize = 1 << 10;
const TRIGGER_LIMIT_INTERNAL: usize = 1 << 12;
const TRIGGER_LIMIT_USER: usize = 1 << 14;

// TODO: SOA implementation of handle values, to accommodate data that is run through
// in groups like this
const CustomTriggerDef = extern struct {
    id: u16,
    fnTrigger: *const fn (*Trig, *Test, BOOL, u16) callconv(.C) void,
    fnInit: ?*const fn (*ModelTriggerDescription, u32, u16) callconv(.C) void,
    fnDestroy: ?*const fn (*Trig, u16) callconv(.C) bool,
    fnUpdate: ?*const fn (*Trig, u16) callconv(.C) void,
    //fnCreate: ?*const fn (*Trig) callconv(.C) void,
};

const CustomTrigger = struct {
    var data: HandleMap(CustomTriggerDef, u16) = undefined;

    // based on loc_47D138 in HandleTriggers
    inline fn basicCleanup(tr: *Trig) void {
        tr.pTrigDesc.Flags |= 1;
        tr.Flags &= 0xFFFFFFFE;
        r.Entity.CallFreeEvent(tr);
    }

    inline fn extractSettings(tr: *Trig) u16 {
        return extractSettingsTD(tr.pTrigDesc);
    }

    inline fn extractSettingsTD(td: *ModelTriggerDescription) u16 {
        return (td.Flags >> 6) & 0b11_1111_1111;
    }

    inline fn find(id: u32) ?*CustomTriggerDef {
        for (data.values.items) |*def|
            if (def.id == @as(u16, @intCast(id))) return def;
        return null;
    }

    pub fn remove(h: Handle(u16)) void {
        _ = data.remove(h);
    }

    pub fn insert(
        owner: u16,
        id: u16,
        fnTrigger: *const fn (*Trig, *Test, BOOL, u16) callconv(.C) void,
        fnInit: ?*const fn (*ModelTriggerDescription, u32, u16) callconv(.C) void,
        fnDestroy: ?*const fn (*Trig, u16) callconv(.C) bool,
        fnUpdate: ?*const fn (*Trig, u16) callconv(.C) void,
        user: bool,
    ) ?Handle(u16) {
        if (id < TRIGGER_LIMIT_GAME) return null;
        if (!user and id >= TRIGGER_LIMIT_INTERNAL) return null;
        if (user and id < TRIGGER_LIMIT_INTERNAL) return null;

        if (find(id)) |_| return null;

        var value = CustomTriggerDef{
            .id = id,
            .fnTrigger = fnTrigger,
            .fnInit = fnInit,
            .fnDestroy = fnDestroy,
            .fnUpdate = fnUpdate,
        };

        return data.insert(owner, value) catch null;
    }

    // replaces Test_HandleTriggers (runs under Test_Callback0x1C)
    // - one-shot triggers that do not need delayed cleanup do Entity_CallFreeEvent here
    // - basic cleanup will be done for you if EntityDestroy or EntityUpdate not defined
    // - else flags |= 1 will be set
    fn hookTrigger(tr: *Trig, te: *Test, is_local: BOOL) callconv(.C) void {
        // FIXME: remove, debug stuff
        t.DrawText(0, 8, "Trigger {d}", .{tr.pTrigDesc.Type}, null, null) catch {};

        if (tr.Type < TRIGGER_LIMIT_GAME) {
            Trig_HandleTriggers(tr, te, is_local);
            return;
        }

        if (find(tr.Type)) |def| {
            def.fnTrigger(tr, te, is_local, extractSettings(tr));
            tr.Flags |= 1;
            if (def.fnDestroy == null and def.fnUpdate == null)
                basicCleanup(tr);
        }
    }

    // inserted into Model_TrigDescInit, after Model_TrigDescAddItem
    // - for one-time setup for non-dynamic stuff, like setting up the cheeseland flames
    fn hookInit(td: *ModelTriggerDescription, flags: u32) callconv(.C) void {
        if (td.Type < TRIGGER_LIMIT_GAME) return;

        if (find(td.Type)) |def| {
            if (def.fnInit == null) return;
            def.fnInit.?(td, flags, extractSettingsTD(td));
        }
    }

    // inserted into Trig_Callback0x14
    // - for delayed cleanup/freeing
    // - runs when trigger active (flags & 1)
    // - return true when the trigger needs to be destroyed
    // - if the trigger is never destroyed then just dont assign a fn here
    // - needs to do its own check for whether to cleanup, and do any model-specific cleanup
    // - but basic trig cleanup will be done for you
    fn hookDestroy(tr: *Trig) callconv(.C) void {
        if (tr.Type < TRIGGER_LIMIT_GAME) return;

        if (find(tr.Type)) |def| {
            if (def.fnDestroy == null) return;
            if (!def.fnDestroy.?(tr, extractSettings(tr))) return;
            basicCleanup(tr);
        }
    }

    // inserted into Trig_Callback0x1C
    // - runs when trigger active (flags & 1)
    fn hookUpdate(tr: *Trig) callconv(.C) void {
        if (tr.Type < TRIGGER_LIMIT_GAME) return;

        if (find(tr.Type)) |def| {
            if (def.fnUpdate == null) return;
            def.fnUpdate.?(tr, extractSettings(tr));
        }
    }

    // Trig_CreateTrigger
    // - only finds entity and inits if needed, no trigger-specific code
    // - original fn may need to be called manually if you do non-dynamic stuff
    //fn hookDoEntityCreate(_: *Trig) callconv(.C) void {}

    const buf = struct {
        var init: [32]u8 = undefined;
        var destroy: [32]u8 = undefined;
        const d_ins = [_]u8{ 0x81, 0x7E, 0x08, 0xF5, 0x01, 0x00, 0x00 }; // cmp dword ptr [esi+08], 0x1F5 (501)
        var update: [32]u8 = undefined;
        const u_ins = [_]u8{ 0x3D, 0x34, 0x01, 0x00, 0x00 }; // cmp eax, 0x134 (308)
    };

    // TODO: verify intergity of hooks; in particular, not 100% on init, but seems
    // fine since it has the same pattern as destroy
    pub fn init(alloc: Allocator) void {
        data = HandleMap(CustomTriggerDef, u16).init(alloc);

        // triggers
        // 0x476E7C -> 0x476E88 (0x0C)
        // 0x476E80 = the actual call instruction
        _ = x86.call(0x476E80, @intFromPtr(&hookTrigger));

        // init
        var init_buf: usize = @intFromPtr(&buf.init);
        var init_addr: usize = 0x47D397;
        const init_end: usize = 0x47D3A0;
        init_addr = x86.jmp(init_addr, init_buf);
        init_buf = x86.push(init_buf, .{ .r32 = .esi });
        init_buf = x86.call(init_buf, @intFromPtr(TriggerDescription_AddItem));
        init_buf = x86.add_esp32(init_buf, 4);
        init_buf = x86.push(init_buf, .{ .r32 = .ebp });
        init_buf = x86.push(init_buf, .{ .r32 = .esi });
        init_buf = x86.call(init_buf, @intFromPtr(&hookInit));
        init_buf = x86.add_esp32(init_buf, 8);
        init_buf = x86.jmp(init_buf, init_addr);
        init_addr = x86.nop_until(init_addr, init_end);

        // destroy
        var destroy_buf: usize = @intFromPtr(&buf.destroy);
        var destroy_addr: usize = 0x47C4D9;
        const destroy_end: usize = 0x47C4E0;
        destroy_addr = x86.jmp(destroy_addr, destroy_buf);
        destroy_buf = x86.push(destroy_buf, .{ .r32 = .esi });
        destroy_buf = x86.call(destroy_buf, @intFromPtr(&hookDestroy));
        destroy_buf = x86.add_esp32(destroy_buf, 4);
        destroy_buf = mem.write_bytes(destroy_buf, &buf.d_ins, 7);
        destroy_buf = x86.jmp(destroy_buf, destroy_addr);
        destroy_addr = x86.nop_until(destroy_addr, destroy_end);

        // update
        var update_buf: usize = @intFromPtr(&buf.update);
        var update_addr: usize = 0x47C51B;
        const update_end: usize = 0x47C520;
        update_addr = x86.jmp(update_addr, update_buf);
        update_buf = x86.save_eax(update_buf);
        update_buf = x86.push(update_buf, .{ .r32 = .esi });
        update_buf = x86.call(update_buf, @intFromPtr(&hookUpdate));
        update_buf = x86.add_esp32(update_buf, 4);
        update_buf = x86.restore_eax(update_buf);
        update_buf = mem.write_bytes(update_buf, &buf.u_ins, 5);
        update_buf = x86.jmp(update_buf, update_addr);
        update_addr = x86.nop_until(update_addr, update_end);
    }

    // FIXME: crashes after reinit -> track load
    // probably due to timing of hotreload or un-cleared triggers
    pub fn deinit() void {
        data.deinit();

        // trigger
        _ = x86.call(0x476E80, @intFromPtr(&Trig_HandleTriggers));

        // init
        var init_addr: usize = 0x47D397;
        init_addr = x86.push(init_addr, .{ .r32 = .esi });
        init_addr = x86.call(init_addr, @intFromPtr(TriggerDescription_AddItem));
        init_addr = x86.add_esp32(init_addr, 4);

        // destroy
        var destroy_addr: usize = 0x47C4D9;
        destroy_addr = mem.write_bytes(destroy_addr, &buf.d_ins, 7);

        // update
        var update_addr: usize = 0x47C51B;
        update_addr = mem.write_bytes(update_addr, &buf.u_ins, 5);
    }
};

fn TriggerBounce(_: *Trig, te: *Test, _: BOOL, settings: u16) callconv(.C) void {
    const strength: f32 = if (settings > 0) @as(f32, @floatFromInt(settings)) / 100 else 1.5;
    te._fall_float_value -= strength;
}

fn TerrainCooldown(te: *Test) callconv(.C) void {
    te.temperature = @min(2 * r.Time.FRAMETIME.* * te.stats.CoolRate + te.temperature, 100);
}

var TerrainCooldownHandle: ?HandleStatic(u16) = null;

const PLUGIN_NAME: [*:0]const u8 = "PluginTest";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return PLUGIN_NAME;
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return PLUGIN_VERSION;
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    CustomTrigger.init(gpa.allocator());
    _ = CustomTrigger.insert(0, 2000, TriggerBounce, null, null, null, false);
    _ = CustomTrigger.insert(0, 5000, TriggerBounce, null, null, null, true);
    TerrainCooldownHandle = gf.RTerrainRequest(0, 0, 18, TerrainCooldown);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    CustomTrigger.deinit();
    if (TerrainCooldownHandle) |h| gf.RTerrainRelease(h);
}

// HOOKS

export fn EarlyEngineUpdateA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    //rt.DrawText(16, 16, "{s} {s}", .{
    //    PLUGIN_NAME,
    //    PLUGIN_VERSION,
    //}, null, null) catch {};
}
