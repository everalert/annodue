const std = @import("std");

const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const AMemory = @import("AMemory.zig");
const Setting = @import("ASettings.zig").Setting;
const SettingHandle = @import("ASettings.zig").Handle;

const MiB = @import("../util/base/base_memory.zig").MiB;
const x86 = @import("../util/x86.zig");
const mem = @import("../util/memory.zig");
const apih = @import("../util/api/api_helper.zig");

const ra = @import("racer").Asset;

// FEATURES
// - expand texture buffer size to allow for a greater number of textures in textureblock
// - SETTINGS:
//   ..             type    note
//   texbuf_enable  bool    requires restart
//   texbuf_size    u32     textureblock texture limit (max 8192); requires restart

// TODO: patch asset buffer, default 2x (16MiB)
// TODO: test realloc to resize texbuf, change to dynamically update buffer size if possible

const TEXBUF_MAX_ITEMS = 8192;

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
    var texbuf_init_det: []u8 = &.{};
    var texbuf_alloc: []u32 = &.{};

    // TODO: ?? not sure about just having a hard limit, while also having the
    //  limit be user-selectable. maybe just switch to hard limit with enable
    //  toggle? hard to predict what a good number would be, or what the point
    //  of this is now really (given the plan to reimpl renderer)
    fn init(gf: *GlobalFn) void {
        texbuf_init_det = apih.AMemoryGetPermanentT(gf, [32]u8) orelse
            @panic("GAssetBuffer(init): API OutOfMemory(Patch)");
        texbuf_alloc = apih.AMemoryGetPermanentT(gf, [TEXBUF_MAX_ITEMS]u32) orelse
            @panic("GAssetBuffer(init): API OutOfMemory(Items)");

        var d: x86.Detour = undefined;

        // patch TextureBuffer_Init (fn_447420)
        if (s_texbuf_enable) {
            d.Start(0x447471, 0x44748D, texbuf_init_det);
            d.addr = x86.call(d.addr, @intFromPtr(&patch_texbuf));
            d.addr = x86.cdecl_call(d.addr, @intFromPtr(ra.Block_Close), &[_]x86.PushSrc{.{ .imm32 = 3 }});
            d.End();
        }
    }

    fn patch_texbuf() callconv(.C) void {
        const tex_count: u32 = @min(TEXBUF_MAX_ITEMS, @max(@max(s_texbuf_size, @as(*u32, @ptrFromInt(0xE9823C)).*), 1700));

        // patch TextureBuffer_LoadModelTexture (fn_447490)
        _ = mem.write(0x4474B1, u32, @intFromPtr(texbuf_alloc.ptr));
        _ = mem.write(0x4474C4, u32, @intFromPtr(texbuf_alloc.ptr));
        _ = mem.write(0x447555, u32, @intFromPtr(texbuf_alloc.ptr));
        // patch TextureBuffer_ClearBufferAfterPtr (fn_4475D0)
        _ = mem.write(0x4475D5, u32, @intFromPtr(texbuf_alloc.ptr));
        _ = mem.write(0x4475E7, u32, @intFromPtr(texbuf_alloc.ptr) + tex_count * 4);
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

pub fn OnInit(gf: *GlobalFn) callconv(.C) void {
    GAssetBuffer.settings_init(gf);
    GAssetBuffer.init(gf);
}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {}
