const std = @import("std");
const user32 = std.os.windows.user32;

const VirtualAlloc = std.os.windows.VirtualAlloc;
const VirtualFree = std.os.windows.VirtualFree;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const MEM_RELEASE = std.os.windows.MEM_RELEASE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;

const MessageBoxA = user32.MessageBoxA;
const MB_OK = user32.MB_OK;
const MB_ICONINFORMATION = user32.MB_ICONINFORMATION;

const ver_major: u32 = 0;
const ver_minor: u32 = 0;
const ver_patch: u32 = 1;

const mp = @import("patch_multiplayer.zig");
const mem = @import("util/memory.zig");
const ini = @import("import/ini/ini.zig");

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

fn PtrMessage(alloc: std.mem.Allocator, ptr: usize, label: []const u8) void {
    var buf = std.fmt.allocPrintZ(alloc, "{s}: 0x{x}", .{ label, ptr }) catch unreachable;
    _ = MessageBoxA(null, buf, "patch.dll", MB_OK);
}

fn PatchDeathSpeed(min: f32, drop: f32) void {
    //0x4C7BB8	4	DeathSpeedMin	float	325.0		SWEP1RCR.EXE+0x0C7BB8
    _ = mem.write(0x4C7BB8, f32, min);
    //0x4C7BBC	4	DeathSpeedDrop	float	140.0		SWEP1RCR.EXE+0x0C7BBC
    _ = mem.write(0x4C7BBC, f32, drop);
}

const IniValue = union(enum) {
    b: bool,
    i: i32,
    u: u32,
    f: f32,
};

const IniValueError = error{
    KeyNotFound,
    NotParseable,
    NotValid,
};

fn SetIniValue(set: *std.StringHashMap(IniValue), key: []const u8, value: []const u8) !void {
    var kv = set.getEntry(key);
    if (kv) |item| {
        return switch (item.value_ptr.*) {
            .b => {
                if (std.mem.eql(u8, "true", value) or value[0] == '1') {
                    item.value_ptr.*.b = true;
                    return;
                }
                if (std.mem.eql(u8, "false", value) or value[0] == '0') {
                    item.value_ptr.*.b = false;
                    return;
                }
                return IniValueError.NotValid;
            },
            .i => {
                item.value_ptr.*.i = try std.fmt.parseInt(i32, value, 10);
            },
            .u => {
                item.value_ptr.*.u = try std.fmt.parseInt(u32, value, 10);
            },
            .f => {
                item.value_ptr.*.f = try std.fmt.parseFloat(f32, value);
            },
        };
    }
}

export fn Patch() void {
    const memory = VirtualAlloc(null, patch_size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE) catch unreachable;
    var off: usize = @intFromPtr(memory);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var gen_s = std.StringHashMap(IniValue).init(alloc);
    defer gen_s.deinit();
    gen_s.put("death_speed_mod_enable", .{ .b = false }) catch unreachable;
    gen_s.put("death_speed_min", .{ .f = 325 }) catch unreachable;
    gen_s.put("death_speed_drop", .{ .f = 140 }) catch unreachable;

    var mp_s = std.StringHashMap(IniValue).init(alloc);
    defer mp_s.deinit();
    mp_s.put("multiplayer_mod_enable", .{ .b = false }) catch unreachable;
    mp_s.put("patch_netplay", .{ .b = false }) catch unreachable;
    mp_s.put("netplay_guid", .{ .b = false }) catch unreachable; // FIXME: causes crash on startup, other untested ones don't
    mp_s.put("netplay_r100", .{ .b = false }) catch unreachable;
    mp_s.put("patch_audio", .{ .b = false }) catch unreachable;
    mp_s.put("patch_fonts", .{ .b = false }) catch unreachable; // working
    mp_s.put("fonts_dump", .{ .b = false }) catch unreachable; // working?
    mp_s.put("patch_tga_loader", .{ .b = false }) catch unreachable;
    mp_s.put("patch_trigger_display", .{ .b = false }) catch unreachable; // working

    var s = std.StringHashMap(*std.StringHashMap(IniValue)).init(alloc);
    defer s.deinit();
    s.put("general", &gen_s) catch unreachable;
    s.put("multiplayer", &mp_s) catch unreachable;

    // ini loading

    const file = std.fs.cwd().openFile("annodue/settings.ini", .{}) catch unreachable;
    defer file.close();

    var parser = ini.parse(alloc, file.reader());
    defer parser.deinit();

    var set: *std.StringHashMap(IniValue) = undefined;
    while (parser.next() catch unreachable) |record| {
        switch (record) {
            .section => |heading| set = s.getEntry(heading).?.value_ptr.*,
            .property => |kv| SetIniValue(set, kv.key, kv.value) catch unreachable,
            .enumeration => |value| _ = value,
        }
    }

    // random stuff

    if (gen_s.get("death_speed_mod_enable").?.b) {
        const dsm = gen_s.get("death_speed_min").?.f;
        const dsd = gen_s.get("death_speed_drop").?.f;
        PatchDeathSpeed(dsm, dsd);
    }

    // swe1r-patcher (multiplayer mod) stuff

    if (mp_s.get("multiplayer_mod_enable").?.b) {
        if (mp_s.get("fonts_dump").?.b) {
            // This is a debug feature to dump the original font textures
            _ = mp.DumpTextureTable(alloc, 0x4BF91C, 3, 0, 64, 128, "font0");
            _ = mp.DumpTextureTable(alloc, 0x4BF7E4, 3, 0, 64, 128, "font1");
            _ = mp.DumpTextureTable(alloc, 0x4BF84C, 3, 0, 64, 128, "font2");
            _ = mp.DumpTextureTable(alloc, 0x4BF8B4, 3, 0, 64, 128, "font3");
            _ = mp.DumpTextureTable(alloc, 0x4BF984, 3, 0, 64, 128, "font4");
        }
        if (mp_s.get("patch_fonts").?.b) {
            off = mp.PatchTextureTable(alloc, off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
            off = mp.PatchTextureTable(alloc, off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
            off = mp.PatchTextureTable(alloc, off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
            off = mp.PatchTextureTable(alloc, off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
            off = mp.PatchTextureTable(alloc, off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
        }
        if (mp_s.get("patch_netplay").?.b) {
            const r100 = mp_s.get("netplay_r100").?.b;
            const guid = mp_s.get("netplay_guid").?.b;
            const traction: u8 = if (r100) 3 else 5;
            var upgrade_lv: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
            var upgrade_hp: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
            const upgrade_lv_ptr: *[7]u8 = @ptrCast(&upgrade_lv);
            const upgrade_hp_ptr: *[7]u8 = @ptrCast(&upgrade_hp);
            off = mp.PatchNetworkUpgrades(off, upgrade_lv_ptr, upgrade_hp_ptr, guid);
            off = mp.PatchNetworkCollisions(off, guid);
        }
        if (mp_s.get("patch_audio").?.b) {
            const sample_rate: u32 = 22050 * 2;
            const bits_per_sample: u8 = 16;
            const stereo: bool = true;
            off = mp.PatchAudioStreamQuality(off, sample_rate, bits_per_sample, stereo);
        }
        if (mp_s.get("patch_tga_loader").?.b) {
            off = mp.PatchSpriteLoaderToLoadTga(off);
        }
        if (mp_s.get("patch_trigger_display").?.b) {
            off = mp.PatchTriggerDisplay(off);
        }
    }

    if (false) {
        var mb_title = std.fmt.allocPrintZ(alloc, "Annodue {d}.{d}.{d}", .{
            ver_major,
            ver_minor,
            ver_patch,
        }) catch unreachable;
        var mb_launch = "Patching SWE1R...";
        _ = MessageBoxA(null, mb_launch, mb_title, MB_OK);
    }
}
