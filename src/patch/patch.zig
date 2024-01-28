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

const mem = @import("util/memory.zig");
const mp = @import("patch_multiplayer.zig");

fn PtrMessage(alloc: std.mem.Allocator, ptr: usize, label: []const u8) void {
    var buf = std.fmt.allocPrintZ(alloc, "{s}: 0x{x}", .{ label, ptr }) catch unreachable;
    _ = MessageBoxA(null, buf, "patch.dll", MB_OK);
}

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

const PATCH_NETPLAY = false;
const NETPLAY_GUID = false; // FIXME: causes crash on startup, other untested ones don't
const NETPLAY_R100 = false;
const PATCH_AUDIO = false;
const PATCH_FONTS = false; // working
const DUMP_FONTS = false; // working?
const PATCH_TRIGGER_DISPLAY = false; // working
const PATCH_TGA_LOADER = false;

fn PatchDeathSpeed(min: f32, drop: f32) void {
    //0x4C7BB8	4	DeathSpeedMin	float	325.0		SWEP1RCR.EXE+0x0C7BB8
    _ = mem.write(0x4C7BB8, f32, min);
    //0x4C7BBC	4	DeathSpeedDrop	float	140.0		SWEP1RCR.EXE+0x0C7BBC
    _ = mem.write(0x4C7BBC, f32, drop);
}

export fn Patch() void {
    const memory = VirtualAlloc(null, patch_size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE) catch unreachable;
    var off: usize = @intFromPtr(memory);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // random stuff

    //PatchDeathSpeed(650, 25);

    // swe1r-patcher (multiplayer mod) stuff

    if (DUMP_FONTS) {
        // This is a debug feature to dump the original font textures
        _ = mp.DumpTextureTable(alloc, 0x4BF91C, 3, 0, 64, 128, "font0");
        _ = mp.DumpTextureTable(alloc, 0x4BF7E4, 3, 0, 64, 128, "font1");
        _ = mp.DumpTextureTable(alloc, 0x4BF84C, 3, 0, 64, 128, "font2");
        _ = mp.DumpTextureTable(alloc, 0x4BF8B4, 3, 0, 64, 128, "font3");
        _ = mp.DumpTextureTable(alloc, 0x4BF984, 3, 0, 64, 128, "font4");
    }

    if (PATCH_FONTS) {
        off = mp.PatchTextureTable(alloc, off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
        off = mp.PatchTextureTable(alloc, off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
        off = mp.PatchTextureTable(alloc, off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
        off = mp.PatchTextureTable(alloc, off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
        off = mp.PatchTextureTable(alloc, off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
    }

    if (PATCH_NETPLAY) {
        const traction = if (NETPLAY_R100) 3 else 5;
        var upgrade_lv: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
        var upgrade_hp: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
        const upgrade_lv_ptr: *[7]u8 = @ptrCast(&upgrade_lv);
        const upgrade_hp_ptr: *[7]u8 = @ptrCast(&upgrade_hp);
        off = mp.PatchNetworkUpgrades(off, upgrade_lv_ptr, upgrade_hp_ptr, NETPLAY_GUID);
        off = mp.PatchNetworkCollisions(off, NETPLAY_GUID);
    }

    if (PATCH_AUDIO) {
        const sample_rate: u32 = 22050 * 2;
        const bits_per_sample: u8 = 16;
        const stereo: bool = true;
        off = mp.PatchAudioStreamQuality(off, sample_rate, bits_per_sample, stereo);
    }

    if (PATCH_TGA_LOADER) {
        off = mp.PatchSpriteLoaderToLoadTga(off);
    }

    if (PATCH_TRIGGER_DISPLAY) {
        off = mp.PatchTriggerDisplay(off);
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
