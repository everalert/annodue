const std = @import("std");

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const HandleStatic = @import("../util/handle_map_static.zig").Handle;
const HandleMapStatic = @import("../util/handle_map_static.zig").HandleMapStatic;
const x86 = @import("../util/x86.zig");

const r = @import("racer");
const t = r.Text;
const Test = r.Entity.Test.Test;
const Test_HandleTerrain = r.Entity.Test.HandleTerrain;
const ModelMesh_GetBehavior = r.Model.Mesh_GetBehavior;

// TERRAIN

// TODO: integrate with core
//   proper interface (add: remove(), ..)
//   global functions
//   owner autoremove on plugin deinit
// TODO: protections to reserve group 3 for internal use
// TODO: testing cleanup

const CustomTerrainDef = extern struct {
    slot: u16,
    fnTerrain: *const fn (*Test) callconv(.C) void,
};

const CustomTerrain = struct {
    var data: HandleMapStatic(CustomTerrainDef, u16, 44) = undefined;

    inline fn find(slot: u16) ?*CustomTerrainDef {
        for (data.values.slice()) |*def|
            if (def.slot == slot) return def;
        return null;
    }

    pub fn remove(h: HandleStatic(u16)) void {
        _ = data.remove(h);
    }

    pub fn insert(
        owner: u16,
        group: u16,
        bit: u16,
        fnTerrain: *const fn (*Test) callconv(.C) void,
    ) ?HandleStatic(u16) {
        std.debug.assert(group <= 3);
        std.debug.assert(bit >= 18 and bit < 29);

        const slot: u16 = group * 11 + bit - 18;
        if (find(slot)) |_| return null;

        var value = CustomTerrainDef{
            .slot = slot,
            .fnTerrain = fnTerrain,
        };
        const handle = data.insert(owner, value) catch return null;
        return handle;
    }

    fn hookDoTerrain(te: *Test) callconv(.C) void {
        Test_HandleTerrain(te);

        const terrain_model = te._unk_0140_terrainModel;
        if (@intFromPtr(terrain_model) == 0) return;
        const behavior = ModelMesh_GetBehavior(terrain_model);
        if (@intFromPtr(behavior) == 0) return;

        const flags = behavior.TerrainFlags;
        const base: u16 = @intCast(((flags >> 30) & 0b11) * 11);
        var custom_flags = (flags >> 18) & 0b0111_1111_1111;
        for (0..11) |i| {
            if ((custom_flags & 1) > 0) {
                const slot: u16 = @intCast(base + i);
                if (find(slot)) |def| def.fnTerrain(te);
            }
            custom_flags >>= 1;
        }

        // FIXME: remove, proof of concept stuff
        t.DrawText(0, 0, "Terrain Flags {b:0>8} {b:0>8} {b:0>8} {b:0>8}", .{
            flags >> 24 & 255,
            flags >> 16 & 255,
            flags >> 8 & 255,
            flags & 255,
        }, null, null) catch {};
    }

    pub fn init() void {
        data = HandleMapStatic(CustomTerrainDef, u16, 44).init() catch unreachable;
        // terrain
        // 0x47B8AF -> 0x47B8B8 (0x09)
        // 0x47B8B0 = the actual call instruction
        _ = x86.call(0x47B8B0, @intFromPtr(&hookDoTerrain));
    }

    pub fn deinit() void {
        _ = x86.call(0x47B8B0, @intFromPtr(&Test_HandleTerrain));
    }
};

// HOOKS

export fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    CustomTerrain.init();
    //_ = CustomTerrain.insert(0, 0, 18, TerrainCooldown);
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    CustomTerrain.deinit();
}
