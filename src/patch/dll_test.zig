const Self = @This();

const std = @import("std");

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const msg = @import("util/message.zig");

// FIXME: remove or whatever, testing
const Handle = @import("util/handle_map_static.zig").Handle;
const HandleMapStatic = @import("util/handle_map_static.zig").HandleMapStatic;
const x86 = @import("util/x86.zig");
const BOOL = std.os.windows.BOOL;
const r = @import("racer");
const Test = r.Entity.Test.Test;
const Test_HandleTerrain = r.Entity.Test.HandleTerrain;
const Trig = r.Entity.Trig.Trig;
const Trig_HandleTriggers = r.Entity.Trig.HandleTriggers;
const t = r.Text;
const mo = r.Model;
const ModelMesh_GetBehavior = mo.Mesh_GetBehavior;
const ModelMesh = mo.ModelMesh;
const ModelBehavior = mo.ModelBehavior;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// -
// - CONTROLS:      keyboard        xinput
//   ..             ..              ..
// - SETTINGS:
//   ..             type    note

fn HandleTriggersHooked(tr: *Trig, te: *Test, is_local: BOOL) callconv(.C) void {
    t.DrawText(0, 8, "Trigger {d}", .{tr.pTrigDesc.Type}, null, null) catch {};

    // iterate over map here..

    // proof of concept stuff
    if (tr.pTrigDesc.Type == 202) te._fall_float_value -= 1.5;

    Trig_HandleTriggers(tr, te, is_local);
}

const CustomTerrainDef = extern struct {
    slot: u16,
    fnTerrain: *const fn (*Test) callconv(.C) void,
};

const CustomTerrain = struct {
    var data = HandleMapStatic(CustomTerrainDef, u16, 44).init() catch unreachable;

    inline fn getSlot(slot: u16) ?*CustomTerrainDef {
        for (data.values.slice()) |*def|
            if (def.slot == slot) return def;
        return null;
    }

    pub fn insertSlot(
        owner: u16,
        group: u16,
        bit: u16,
        fnTerrain: *const fn (*Test) callconv(.C) void,
    ) ?Handle(u16) {
        std.debug.assert(group <= 3);
        std.debug.assert(bit >= 18 and bit < 29);

        const slot: u16 = group * 11 + bit - 18;
        if (getSlot(slot)) |_| return null;

        var value = CustomTerrainDef{
            .slot = slot,
            .fnTerrain = fnTerrain,
        };
        const handle = data.insert(owner, value) catch return null;
        return handle;
    }

    fn hook(te: *Test) callconv(.C) void {
        Test_HandleTerrain(te);

        const terrain_model = te._unk_0140_terrainModel;
        if (@intFromPtr(terrain_model) == 0) return;
        const behavior = ModelMesh_GetBehavior(terrain_model);
        if (@intFromPtr(behavior) == 0) return;

        const flags = behavior.TerrainFlags;
        const base: u16 = @intCast((flags & 0b11) * 11);
        var custom_flags = (flags >> 3) & 0b0111_1111_1111;
        for (0..11) |i| {
            defer custom_flags >>= 1;
            if ((custom_flags & 1) > 0) {
                const id: u16 = base + 11 - @as(u16, @intCast(i)) - 1;
                if (getSlot(id)) |def| def.fnTerrain(te);
            }
        }

        // proof of concept stuff
        t.DrawText(0, 0, "Terrain Flags {b:0>8} {b:0>8} {b:0>8} {b:0>8}", .{
            flags >> 24 & 255,
            flags >> 16 & 255,
            flags >> 8 & 255,
            flags & 255,
        }, null, null) catch {};
        //if (flags & (1 << 5) > 0) // SLIP terrain
        //    te.temperature = @min(2 * r.Time.FRAMETIME.* * te.stats.CoolRate + te.temperature, 100);
    }
};

fn TerrainCooldown(te: *Test) callconv(.C) void {
    te.temperature = @min(2 * r.Time.FRAMETIME.* * te.stats.CoolRate + te.temperature, 100);
}

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

export fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // triggers
    // 0x476E7C -> 0x476E88 (0x0C)
    // 0x476E80 = the actual call instruction
    _ = x86.call(0x476E80, @intFromPtr(&HandleTriggersHooked));

    // terrain
    // 0x47B8AF -> 0x47B8B8 (0x09)
    // 0x47B8B0 = the actual call instruction
    _ = x86.call(0x47B8B0, @intFromPtr(&CustomTerrain.hook));
    _ = CustomTerrain.insertSlot(0, 0, 18, TerrainCooldown);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    // deinit here
    _ = x86.call(0x476E80, @intFromPtr(&Trig_HandleTriggers));
    _ = x86.call(0x47B8B0, @intFromPtr(&Test_HandleTerrain));
}

// HOOKS

export fn EarlyEngineUpdateA(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    const s = struct {
        const beachpp: **mo.ModelNode = @ptrFromInt(0xE287E8);
        var bit1: bool = true;
        var bit2: bool = true;
    };

    if (gf.InputGetKbRaw(.J) == .JustOn) {
        if (s.bit1) {
            mo.Node_SetFlags(s.beachpp.*, 2, 0b01, 0x10, 2); // flags |= 0x00000001
        } else {
            mo.Node_SetFlags(s.beachpp.*, 2, -2, 0x10, 3); // flags &= 0xFFFFFFFE
        }
        s.bit1 = !s.bit1;
    }
    if (gf.InputGetKbRaw(.F) == .JustOn) {
        if (s.bit2) {
            mo.Node_SetFlags(s.beachpp.*, 2, 0b10, 0x10, 2); // flags |= 0x00000002
        } else {
            mo.Node_SetFlags(s.beachpp.*, 2, -3, 0x10, 3); // flags &= 0xFFFFFFFD
        }
        s.bit2 = !s.bit2;
    }

    //rt.DrawText(16, 16, "{s} {s}", .{
    //    PLUGIN_NAME,
    //    PLUGIN_VERSION,
    //}, null, null) catch {};
}
