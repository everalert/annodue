const std = @import("std");

const Allocator = std.mem.Allocator;
const BOOL = std.os.windows.BOOL;

const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const workingOwner = @import("Hook.zig").PluginState.workingOwner;
const coreAllocator = @import("Allocator.zig").allocator;

const SettingHandle = @import("ASettings.zig").Handle;
const SettingValue = @import("ASettings.zig").ASettingSent.Value;
const Setting = @import("ASettings.zig").ASettingSent;

const Handle = @import("../util/handle_map.zig").Handle;
const HandleMap = @import("../util/handle_map.zig").HandleMap;
const x86 = @import("../util/x86.zig");
const mem = @import("../util/memory.zig");

const r = @import("racer");
const t = r.Text;
const Test = r.Entity.Test.Test;
const Trig = r.Entity.Trig.Trig;
const Trig_HandleTriggers = r.Entity.Trig.HandleTriggers;
const TriggerDescription_AddItem = r.Model.TriggerDescription_AddItem;
const ModelTriggerDescription = r.Model.ModelTriggerDescription;

// TODO: cleanup commenting around functions; consolidate relevant info for plugin devs
// TODO: cleanup hand-rolled assembly, once more work on generalizing x86 util done

// TODO: finish writing out FEATURES section according to below todo, and mirror in MANUAL.md
// TODO: explain lifecycle of a trigger common model-entity interactions at each stage, etc.
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

// FEATURES
// - ..
// - Show race trigger interactions via game notification system
// - SETTINGS:
//   notify_trigger     bool

pub const THandle = Handle(u16);
pub const THandleMap = HandleMap(CustomTriggerDef, u16);
const TNullHandle = THandle.getNull();

const TRIGGER_LIMIT_GAME: usize = 1 << 10;
const TRIGGER_LIMIT_INTERNAL: usize = 1 << 12;
const TRIGGER_LIMIT_USER: usize = (1 << 16) - 1;

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
    var data: THandleMap = undefined;

    var h_s_section: ?SettingHandle = null;
    var h_s_notify_trigger: ?SettingHandle = null;
    var s_notify_trigger: bool = false;

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

    pub fn remove(h: THandle) void {
        _ = data.remove(h);
    }

    pub fn removeAll(owner: u16) void {
        _ = data.removeOwner(owner);
    }

    pub fn insert(
        owner: u16,
        id: u16,
        fnTrigger: *const fn (*Trig, *Test, BOOL, u16) callconv(.C) void,
        fnInit: ?*const fn (*ModelTriggerDescription, u32, u16) callconv(.C) void,
        fnDestroy: ?*const fn (*Trig, u16) callconv(.C) bool,
        fnUpdate: ?*const fn (*Trig, u16) callconv(.C) void,
        user: bool,
    ) ?THandle {
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
        // TODO: move to internal Toast system; spam queueing an issue
        if (s_notify_trigger) {
            var b: [127:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&b, "Trigger {d} activated", .{tr.Type}) catch {};
            t.swrText_NewNotification(&b, 3.0);
        }

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
        var update: [48]u8 = undefined;
    };

    // TODO: verify intergity of hooks; in particular, not 100% on init, but seems
    // fine since it has the same pattern as destroy; may also want save_esi on destroy
    pub fn init(alloc: Allocator) void {
        var d: x86.Detour = undefined;
        data = THandleMap.init(alloc);

        // triggers
        // 0x476E7C -> 0x476E88 (0x0C)
        // 0x476E80 = the actual call instruction
        _ = x86.call(0x476E80, @intFromPtr(&hookTrigger));

        // init
        x86.detour_start(&d, 0x47D397, 0x47D3A0, &buf.init);
        d.addr = x86.cdecl_call(d.addr, @intFromPtr(TriggerDescription_AddItem), &[_]x86.PushSrc{.{ .r32 = .esi }});
        d.addr = x86.cdecl_call(d.addr, @intFromPtr(&hookInit), &[_]x86.PushSrc{ .{ .r32 = .esi }, .{ .r32 = .ebp } });
        x86.detour_end(&d);

        // destroy
        x86.detour_start(&d, 0x47C4D9, 0x47C4E0, &buf.destroy);
        d.addr = x86.cdecl_call(d.addr, @intFromPtr(&hookDestroy), &[_]x86.PushSrc{.{ .r32 = .esi }});
        d.addr = x86.CMP(d.addr, .esi, 0x08, .imm, 0x1F5);
        x86.detour_end(&d);

        // update
        x86.detour_start(&d, 0x47C51B, 0x47C520, &buf.update);
        d.addr = x86.reg_save(d.addr, .eax, .ebp); // TODO: is this detour meant to replace a function body?
        d.addr = x86.cdecl_call(d.addr, @intFromPtr(&hookUpdate), &[_]x86.PushSrc{.{ .r32 = .esi }});
        d.addr = x86.reg_restore(d.addr, .eax, .ebp);
        d.addr = x86.CMP(d.addr, .eax, null, .imm, 0x134);
        x86.detour_end(&d);
    }

    // FIXME: crashes after reinit -> track load
    // probably due to timing of hotreload or un-cleared triggers
    pub fn deinit() void {
        data.deinit();

        // trigger
        _ = x86.call(0x476E80, @intFromPtr(&Trig_HandleTriggers));

        // init
        // WARN: cdecl_call ends with add_esp8, which is fewer bytes than the source
        // asm, but should not cause problems in this case; safer if auto asm restore
        // implemented in x86 util detour functions though
        _ = x86.cdecl_call(0x47D397, @intFromPtr(TriggerDescription_AddItem), &[_]x86.PushSrc{.{ .r32 = .esi }});

        // destroy
        _ = x86.CMP(0x47C4D9, .esi, 0x08, .imm, 0x1F5);

        // update
        _ = x86.CMP(0x47C51B, .eax, null, .imm, 0x134);
    }

    fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "core/RTrigger", null);
        h_s_section = section;

        h_s_notify_trigger =
            gf.ASettingOccupy(section, "notify_trigger", .B, .{ .b = false }, &s_notify_trigger, null);
    }
};

// GLOBAL EXPORTS

/// attempt to define a new custom trigger id with behaviour
/// returns handle to resource if acquisition success, 'null' handle if failed
/// @id         4096..65534
/// @fnTrigger
/// @fnInit
/// @fnDestroy
/// @fnUpdate
pub fn RRequest(
    id: u16,
    fnTrigger: *const fn (*Trig, *Test, BOOL, u16) callconv(.C) void,
    fnInit: ?*const fn (*ModelTriggerDescription, u32, u16) callconv(.C) void,
    fnDestroy: ?*const fn (*Trig, u16) callconv(.C) bool,
    fnUpdate: ?*const fn (*Trig, u16) callconv(.C) void,
) callconv(.C) THandle {
    if (id < TRIGGER_LIMIT_INTERNAL) return TNullHandle;
    return CustomTrigger.insert(workingOwner(), id, fnTrigger, fnInit, fnDestroy, fnUpdate, true) orelse TNullHandle;
}

/// release a single handle
pub fn RRelease(h: THandle) callconv(.C) void {
    CustomTrigger.remove(h);
}

/// release all handles held by the plugin
pub fn RReleaseAll() callconv(.C) void {
    CustomTrigger.removeAll(workingOwner());
}

// HOOKS

pub fn OnInit(gf: *GlobalFn) callconv(.C) void {
    CustomTrigger.init(coreAllocator());
    CustomTrigger.settingsInit(gf);
}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {
    CustomTrigger.deinit();
}

pub fn OnPluginDeinitA(owner: u16) callconv(.C) void {
    CustomTrigger.removeAll(owner);
}

// TODO: reintroduce when 'debug readout' thing is done
//const rt = r.Text;
//pub fn Draw2DB(_: *GlobalFn) callconv(.C) void {
//    rt.DrawText(0, 0, "TRIGGERS: {d}", .{CustomTrigger.data.values.items.len}, null, null) catch {};
//    for (CustomTrigger.data.handles.items, 0..) |h, i|
//        rt.DrawText(0, @intCast(8 + 8 * i), "{X:0>4} o:{X:0>4} g:{X:0>4} i:{X:0>4}", .{
//            i, h.owner, h.generation, h.index,
//        }, null, null) catch {};
//}
