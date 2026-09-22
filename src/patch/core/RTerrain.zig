const std = @import("std");

const PluginAPI = @import("../util/root.zig").PluginAPI;

const WorkingOwner = @import("AHook.zig").PluginState.WorkingOwner;

const HandleStatic = @import("../util/handle_map_static.zig").Handle;
const HandleMapStatic = @import("../util/handle_map_static.zig").HandleMapStatic;
const x86 = @import("../util/x86.zig");
const plugh = @import("../util/plugin/plugin_helper.zig");
const RAddressHandleInfo = plugh.RAddressHandleInfo;
const RAddressHandle = @import("../util/plugin/plugin.zig").RAddressHandle;

const r = @import("racer");
const Test = r.Entity.Test.Test;
const Test_HandleTerrain = r.Entity.Test.HandleTerrain;
const ModelMesh_GetBehavior = r.Model.Mesh_GetBehavior;

// TERRAIN

pub const THandle = HandleStatic(u16);
pub const THandleMap = HandleMapStatic(CustomTerrainDef, u16, 44);
const TNullHandle = THandle.getNull();

const CustomTerrainDef = extern struct {
    slot: u16,
    fnTerrain: *const fn (*Test) callconv(.C) void,
};

const CustomTerrain = struct {
    var data: THandleMap = undefined;

    var h_ar_hook = RAddressHandleInfo.InitLen(0x47B8B0, 5);

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
        bit: u16,
        group: u16,
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
        if (terrain_model == null) return;
        const behavior = ModelMesh_GetBehavior(terrain_model.?);
        if (behavior == null) return;

        const flags = @as(u32, @bitCast(behavior.?.TerrainFlags));
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

    pub fn init(api: *PluginAPI) void {
        data = THandleMap.init() catch unreachable;

        h_ar_hook.Reserve(api);

        // terrain
        // 0x47B8AF -> 0x47B8B8 (0x09)
        // 0x47B8B0 = the actual call instruction
        if (api.RAddressRangeWriteSt(h_ar_hook.Handle)) {
            defer api.RAddressRangeWriteEd(h_ar_hook.Handle);
            _ = x86.call(0x47B8B0, @intFromPtr(&hookDoTerrain));
        }
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
    bit: u16,
    group: u16,
    fnTerrain: *const fn (*Test) callconv(.C) void,
) callconv(.C) THandle {
    if (group > 2) return TNullHandle;
    if (bit < 18 or bit >= 29) return TNullHandle;
    return CustomTerrain.insert(WorkingOwner(), bit, group, fnTerrain, true) orelse TNullHandle;
}

/// release a single handle
pub fn RRelease(h: THandle) callconv(.C) void {
    CustomTerrain.remove(h);
}

/// release all handles held by the plugin
pub fn RReleaseAll() callconv(.C) void {
    CustomTerrain.removeAll(WorkingOwner());
}

// HOOKS

pub fn OnInit(api: *PluginAPI) callconv(.C) void {
    CustomTerrain.init(api);
}

pub fn OnInitLate(_: *PluginAPI) callconv(.C) void {}

pub fn OnDeinit(_: *PluginAPI) callconv(.C) void {}

pub fn OnPluginDeinitA(owner: u16) callconv(.C) void {
    CustomTerrain.removeAll(owner);
}

// TODO: reintroduce when 'debug readout' thing is done
//const rt = r.Text;
//pub fn Draw2DB(_: *PluginAPI) callconv(.C) void {
//    rt.DrawText(320, 0, "TERRAINS: {d}", .{CustomTerrain.data.values.len}, null, null) catch {};
//    for (CustomTerrain.data.handles.constSlice(), 0..) |h, i|
//        rt.DrawText(320, @intCast(8 + 8 * i), "{X:0>4} o:{X:0>4} g:{X:0>4} i:{X:0>4}", .{
//            i, h.owner, h.generation, h.index,
//        }, null, null) catch {};
//}
