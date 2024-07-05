const Self = @This();

const std = @import("std");

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// - Disable multiplayer collisions
// - Max upgrades in multiplayer
// - Patch GUID to prevent joined players using different multiplayer settings
// - SETTINGS:
//   * all settings require game restart to apply
//   enable         bool
//   patch_guid     bool
//   patch_r100     bool    Use R-100 traction in the patched upgrade stack

// TODO: custom upgrades; user-level upgrades
// TODO: fix/reimpl GUID to be more robust
// TODO: remaining settings for every aspect? (collisions, etc.)
// TODO: make settings hot-reloadable (see comment in OnInit)

const PLUGIN_NAME: [*:0]const u8 = "Multiplayer";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const MpState = struct {
    var mp_enable: bool = false;
    var patch_r100: bool = false;
    var patch_guid: bool = false;
};

fn HandleSettings(gf: *GlobalFn) callconv(.C) void {
    MpState.mp_enable = gf.SettingGetB("multiplayer", "enable").?;
    MpState.patch_r100 = gf.SettingGetB("multiplayer", "patch_r100").?;
    MpState.patch_guid = gf.SettingGetB("multiplayer", "patch_guid").?;
}

// PATCHES

// NOTE: max data size 256
// FIXME: new guid not equivalent to swe1r-patcher for some reason, but close
// maybe redo the whole thing with a new algo, or just scrap it
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
    //offset = x86.push_edx(offset);
    offset = x86.push(offset, .{ .r32 = .edx });
    //offset = x86.push_eax(offset);
    offset = x86.push(offset, .{ .r32 = .eax });
    //offset = x86.push_u32(offset, off_up_hp);
    offset = x86.push(offset, .{ .imm32 = off_up_hp });
    //offset = x86.push_u32(offset, off_up_lv);
    offset = x86.push(offset, .{ .imm32 = off_up_lv });
    //offset = x86.push_esi(offset);
    offset = x86.push(offset, .{ .r32 = .esi });
    //offset = x86.push_edi(offset);
    offset = x86.push(offset, .{ .r32 = .edi });
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
    //offset = x86.push_edx(offset);
    offset = x86.push(offset, .{ .r32 = .edx });
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
    return PLUGIN_NAME;
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return PLUGIN_VERSION;
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    HandleSettings(gf);

    // TODO: move this to settings handler, once global allocation figured out
    var off = gs.patch_offset;
    if (MpState.mp_enable) {
        const traction: u8 = if (MpState.patch_r100) 3 else 5;
        var upgrade_lv: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
        var upgrade_hp: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
        const upgrade_lv_ptr: *[7]u8 = @ptrCast(&upgrade_lv);
        const upgrade_hp_ptr: *[7]u8 = @ptrCast(&upgrade_hp);
        off = PatchNetworkUpgrades(off, upgrade_lv_ptr, upgrade_hp_ptr, MpState.patch_guid);
        off = PatchNetworkCollisions(off, MpState.patch_guid);
    }
    gs.patch_offset = off;
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

// HOOKS

export fn OnSettingsLoad(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    HandleSettings(gf);
}
