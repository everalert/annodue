const std = @import("std");

const Allocator = std.mem.Allocator;
const BOOL = std.os.windows.BOOL;

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const workingOwner = @import("Hook.zig").PluginState.workingOwner;
const coreAllocator = @import("Allocator.zig").allocator;

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
    // fine since it has the same pattern as destroy; may also want save_esi on destroy
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
) callconv(.C) Handle(u16) {
    if (id < TRIGGER_LIMIT_INTERNAL) return .{};
    return CustomTrigger.insert(workingOwner(), id, fnTrigger, fnInit, fnDestroy, fnUpdate, true) orelse .{};
}

/// release a single handle
pub fn RRelease(h: Handle(u16)) callconv(.C) void {
    CustomTrigger.remove(h);
}

/// release all handles held by the plugin
pub fn RReleaseAll() callconv(.C) void {
    CustomTrigger.removeAll(workingOwner());
}

// HOOKS

export fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    CustomTrigger.init(coreAllocator());
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    CustomTrigger.deinit();
}

pub fn OnPluginDeinit(owner: u16) callconv(.C) void {
    CustomTrigger.removeAll(owner);
}
