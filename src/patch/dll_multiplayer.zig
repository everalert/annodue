const Self = @This();

const std = @import("std");

const GlobalState = @import("global.zig").GlobalState;
const GlobalVTable = @import("global.zig").GlobalVTable;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const r = @import("util/racer.zig");
const rf = @import("util/racer_fn.zig");

const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

//plugin/Multiplayer
//- mp: patch network collisions
//- mp: patch network upgrades

// NETPLAY PATCHES

// NOTE: max data size 256
// FIXME: new guid not equivalent to swe1r-patcher for some reason, but close
fn ModifyNetworkGuid(data: []u8) void {
    // RC4 hash
    const state = struct {
        var s: [256]u8 = undefined;
        var initialized: bool = false;
    };
    if (!state.initialized) {
        var i: usize = 0;
        while (i < 256) : (i += 1) {
            state.s[i] = @truncate(i);
        }
        state.initialized = true;
    }

    std.debug.assert(data.len <= 256);
    var i: usize = 0;
    var j: u8 = 0;
    while (i < 256) : (i += 1) {
        j +%= state.s[i] +% data[i % data.len];
        std.mem.swap(u8, &state.s[i], &state.s[j]);
    }

    var k_i: u8 = 0;
    var k_j: u8 = 0;
    var k_s: [256]u8 = undefined;
    @memcpy(&k_s, &state.s);
    i = 0;
    while (i < 16) : (i += 1) {
        k_i += 1;
        k_j +%= k_s[k_i];
        std.mem.swap(u8, &k_s[k_i], &k_s[k_j]);
        var idx: usize = (@as(usize, k_s[k_i]) + k_s[k_j]) % 0xFF;
        var rc4_output: u8 = k_s[idx];
        _ = mem.write(0x4AF9B0 + i, u8, rc4_output);
    }

    // Overwrite the first 2 byte with a version index, so we have room
    // to fix the algorithm if we have messed up
    _ = mem.write(0x4AF9B0 + 0, u16, 0x00000000);
}

fn PatchNetworkUpgrades(memory_offset: usize, upgrade_levels: *[7]u8, upgrade_healths: *[7]u8, patch_guid: bool) usize {
    if (patch_guid) {
        ModifyNetworkGuid(@constCast("Upgrades"));
        ModifyNetworkGuid(upgrade_levels);
        ModifyNetworkGuid(upgrade_healths);
    }

    var offset: usize = memory_offset;

    // Update menu upgrades
    _ = mem.write(0x45CFC6, u8, 0x05); // levels
    _ = mem.write(0x45CFCB, u8, 0xFF); // healths

    // Place upgrade data in memory
    const off_up_lv: usize = offset;
    offset = mem.write(offset, @TypeOf(upgrade_levels.*), upgrade_levels.*);
    const off_up_hp: usize = offset;
    offset = mem.write(offset, @TypeOf(upgrade_healths.*), upgrade_healths.*);

    // Construct our code
    const off_upgrade_code: usize = offset;
    offset = x86.push_edx(offset);
    offset = x86.push_eax(offset);
    offset = x86.push_u32(offset, off_up_hp);
    offset = x86.push_u32(offset, off_up_lv);
    offset = x86.push_esi(offset);
    offset = x86.push_edi(offset);
    offset = x86.call(offset, 0x449D00); // ???
    offset = x86.add_esp8(offset, 0x10);
    offset = x86.pop_eax(offset);
    offset = x86.pop_edx(offset);
    offset = x86.retn(offset);

    // Install it by jumping from 0x45B765 and returning to 0x45B76C
    var off_install: usize = 0x45B765;
    off_install = x86.call(off_install, off_upgrade_code);
    off_install = x86.nop(off_install);
    off_install = x86.nop(off_install);

    return offset;
}

// WARNING: not tested
fn PatchNetworkCollisions(memory_offset: usize, patch_guid: bool) usize {
    // Disable collision between network players
    if (patch_guid) {
        ModifyNetworkGuid(@constCast("Collisions"));
    }

    var offset: usize = memory_offset;
    const memory_offset_collision_code: usize = memory_offset;

    // Inject new code
    offset = x86.push_edx(offset);
    offset = x86.mov_edx(offset, 0x4D5E00); // _dword_4D5E00_is_multiplayer
    offset = x86.test_edx_edx(offset);
    offset = x86.pop_edx(offset);
    offset = x86.jz(offset, 0x47B0C0);
    offset = x86.retn(offset);

    // Install it by patching call at 0x47B5AF
    _ = mem.write(0x47B5AF + 1, u32, memory_offset_collision_code - (0x47B5AF + 5));

    return offset;
}

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return "Multiplayer";
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return "0.0.1";
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = initialized;
    var off = gs.patch_offset;
    if (gv.SettingGetB("multiplayer", "multiplayer_mod_enable").?) {
        if (gv.SettingGetB("multiplayer", "patch_netplay").?) {
            const r100 = gv.SettingGetB("multiplayer", "netplay_r100").?;
            const guid = gv.SettingGetB("multiplayer", "netplay_guid").?;
            const traction: u8 = if (r100) 3 else 5;
            var upgrade_lv: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
            var upgrade_hp: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
            const upgrade_lv_ptr: *[7]u8 = @ptrCast(&upgrade_lv);
            const upgrade_hp_ptr: *[7]u8 = @ptrCast(&upgrade_hp);
            off = PatchNetworkUpgrades(off, upgrade_lv_ptr, upgrade_hp_ptr, guid);
            off = PatchNetworkCollisions(off, guid);
        }
    }
    gs.patch_offset = off;
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

// HOOKS

export fn EarlyEngineUpdateAfter(gs: *GlobalState, gv: *GlobalVTable, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}
