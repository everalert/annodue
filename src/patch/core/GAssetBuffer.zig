const std = @import("std");

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const coreAllocator = @import("Allocator.zig").allocator;
const Setting = @import("ASettings.zig").Setting;
const SettingHandle = @import("ASettings.zig").Handle;

const x86 = @import("../util/x86.zig");
const mem = @import("../util/memory.zig");
const PPanic = @import("../util/debug.zig").PPanic;

const ra = @import("racer").Asset;

// FIXME: remove, for testing
const dbg = @import("../util/debug.zig");

// TODO: test realloc to resize buf
// TODO: also resize asset buffer to 2x

const GAssetBuffer = struct {
    var h_s_section: ?SettingHandle = null;
    var h_s_texbuf_enable: ?SettingHandle = null;
    var h_s_texbuf_size: ?SettingHandle = null;
    var s_texbuf_enable: bool = false;
    var s_texbuf_size: u32 = 5120; // unpatched: 1700

    // NOTE: original code replaced in TextureBuffer_Init
    //if (ra.TextureBlockCount.* > 1700)
    //    while (true) {};
    //@memset(ra.TextureBuffer, 0);
    //ra.Block_Close(.Texture);
    const texbuf_init_src = [_]u8{
        0x7E, 0x02, 0xEB, 0xFE, 0xB9, 0xA4, 0x06, 0x00, 0x00, 0x33, 0xC0,
        0xBF, 0x60, 0x38, 0xE9, 0x00, 0x6A, 0x03, 0xF3, 0xAB, 0xE8, 0x66,
        0x62, 0xFE, 0xFF, 0x83, 0xC4, 0x04,
    };
    var texbuf_init_det: [32]u8 = undefined;
    var texbuf_alloc: ?[]u32 = undefined;

    fn init() void {
        var d: x86.Detour = undefined;

        // patch TextureBuffer_Init (fn_447420)
        if (s_texbuf_enable) {
            x86.detour_start(&d, 0x447471, 0x44748D, &texbuf_init_det);
            d.addr = x86.call(d.addr, @intFromPtr(&patch_texbuf));
            d.addr = x86.cdecl_call(d.addr, @intFromPtr(ra.Block_Close), &[_]x86.PushSrc{.{ .imm32 = 3 }});
            x86.detour_end(&d);
        }
    }

    fn patch_texbuf() callconv(.C) void {
        const tex_count: u32 = @max(@max(s_texbuf_size, @as(*u32, @ptrFromInt(0xE9823C)).*), 1700);
        texbuf_alloc = coreAllocator().alloc(u32, tex_count) catch |err|
            PPanic("patch_texbuf_init: allocation failed - {s}", .{@errorName(err)});
        //@memset(texbuf_alloc, 0);  // NOTE: seems to be unnecessary

        // patch TextureBuffer_LoadModelTexture (fn_447490)
        _ = mem.write(0x4474B1, u32, @intFromPtr(texbuf_alloc.?.ptr));
        _ = mem.write(0x4474C4, u32, @intFromPtr(texbuf_alloc.?.ptr));
        _ = mem.write(0x447555, u32, @intFromPtr(texbuf_alloc.?.ptr));
        // patch TextureBuffer_ClearBufferAfterPtr (fn_4475D0)
        _ = mem.write(0x4475D5, u32, @intFromPtr(texbuf_alloc.?.ptr));
        _ = mem.write(0x4475E7, u32, @intFromPtr(texbuf_alloc.?.ptr + tex_count));
    }

    fn settings_init(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "core/GAssetBuffer", null);
        h_s_section = section;

        h_s_texbuf_enable =
            gf.ASettingOccupy(section, "texbuf_enable", .B, .{ .b = false }, &s_texbuf_enable, null);
        h_s_texbuf_size =
            gf.ASettingOccupy(section, "texbuf_size", .U, .{ .u = 5120 }, &s_texbuf_size, null);
    }
};

// HOOKS

pub fn OnInit(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    GAssetBuffer.settings_init(gf);
    GAssetBuffer.init();
}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}
