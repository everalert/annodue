const std = @import("std");

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;
const workingOwner = &@import("Hook.zig").PluginState.workingOwner;

const HandleStatic = @import("../util/handle_map_static.zig").Handle;
const HandleMapStatic = @import("../util/handle_map_static.zig").HandleMapStatic;
const x86 = @import("../util/x86.zig");

const r = @import("racer");
const t = r.Text;
const Test = r.Entity.Test.Test;
const Test_HandleTerrain = r.Entity.Test.HandleTerrain;
const ModelMesh_GetBehavior = r.Model.Mesh_GetBehavior;

// TERRAIN

// TODO: move 'bit' arg before 'group' on insert()/RRequest()?

pub const THandle = HandleStatic(u16);
pub const THandleMap = HandleMapStatic(CustomTerrainDef, u16, 44);
const TNullHandle = THandle.getNull();

const CustomTerrainDef = extern struct {
    slot: u16,
    fnTerrain: *const fn (*Test) callconv(.C) void,
};

const CustomTerrain = struct {
    var data: THandleMap = undefined;

    inline fn find(slot: u16) ?*CustomTerrainDef {
        for (data.values.slice()) |*def|
            if (def.slot == slot) return def;
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
        group: u16,
        bit: u16,
        fnTerrain: *const fn (*Test) callconv(.C) void,
        user: bool,
    ) ?THandle {
        std.debug.assert(group <= 3);
        std.debug.assert(bit >= 18 and bit < 29);
        if (!user and group < 3) return null;
        if (user and group == 3) return null;

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
    }

    pub fn init() void {
        data = THandleMap.init() catch unreachable;
        // terrain
        // 0x47B8AF -> 0x47B8B8 (0x09)
        // 0x47B8B0 = the actual call instruction
        _ = x86.call(0x47B8B0, @intFromPtr(&hookDoTerrain));
    }

    pub fn deinit() void {
        _ = x86.call(0x47B8B0, @intFromPtr(&Test_HandleTerrain));
    }
};

// GLOBAL EXPORTS

/// attempt to add behaviour to a terrain flag
/// returns handle to resource if acquisition success, 'null' handle if failed
/// @owner
/// @group      0..2
/// @bit        18..28
/// @fnTerrain
pub fn RRequest(
    group: u16,
    bit: u16,
    fnTerrain: *const fn (*Test) callconv(.C) void,
) callconv(.C) THandle {
    if (group > 2) return TNullHandle;
    if (bit < 18 or bit >= 29) return TNullHandle;
    return CustomTerrain.insert(workingOwner(), group, bit, fnTerrain, true) orelse TNullHandle;
}

/// release a single handle
pub fn RRelease(h: THandle) callconv(.C) void {
    CustomTerrain.remove(h);
}

/// release all handles held by the plugin
pub fn RReleaseAll() callconv(.C) void {
    CustomTerrain.removeAll(workingOwner());
}

// HOOKS

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    CustomTerrain.init();
}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    CustomTerrain.deinit();
}

pub fn OnPluginDeinit(owner: u16) callconv(.C) void {
    CustomTerrain.removeAll(owner);
}

// TODO: reintroduce when 'debug readout' thing is done
//const rt = r.Text;
//pub fn Draw2DB(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
//    rt.DrawText(320, 0, "TERRAINS: {d}", .{CustomTerrain.data.values.len}, null, null) catch {};
//    for (CustomTerrain.data.handles.constSlice(), 0..) |h, i|
//        rt.DrawText(320, @intCast(8 + 8 * i), "{X:0>4} o:{X:0>4} g:{X:0>4} i:{X:0>4}", .{
//            i, h.owner, h.generation, h.index,
//        }, null, null) catch {};
//}
