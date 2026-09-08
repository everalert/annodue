const std = @import("std");

const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;

const AMemory = @import("AMemory.zig");
const Setting = @import("ASettings.zig").Setting;
const SettingHandle = @import("ASettings.zig").Handle;

const MiB = @import("../util/base/base_memory.zig").MiB;
const x86 = @import("../util/x86.zig");
const mem = @import("../util/memory.zig");
const apih = @import("../util/api/api_helper.zig");
const RAddressHandleInfo = apih.RAddressHandleInfo;

const RAddressHandle = @import("../util/api/api.zig").RAddressHandle;
const RADDRESS_HANDLE_NULL = @import("../util/api/api.zig").RADDRESS_HANDLE_NULL;

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

    var h_ar_detour = RAddressHandleInfo.Init(0x447471, 0x44748D);
    var h_ar_bufref1 = RAddressHandleInfo.InitLen(0x4474B1, 4);
    var h_ar_bufref2 = RAddressHandleInfo.InitLen(0x4474C4, 4);
    var h_ar_bufref3 = RAddressHandleInfo.InitLen(0x447555, 4);
    var h_ar_bufref4 = RAddressHandleInfo.InitLen(0x4475D5, 4);
    var h_ar_bufref5 = RAddressHandleInfo.InitLen(0x4475E7, 4);

    var texbuf_init_det: []u8 = &.{};
    var texbuf_alloc: []u32 = &.{};

    var api: *GlobalFn = undefined;

    // TODO: ?? not sure about just having a hard limit, while also having the
    //  limit be user-selectable. maybe just switch to hard limit with enable
    //  toggle? hard to predict what a good number would be, or what the point
    //  of this is now really (given the plan to reimpl renderer)
    fn init() void {
        h_ar_detour.Reserve(api);
        h_ar_bufref1.Reserve(api);
        h_ar_bufref2.Reserve(api);
        h_ar_bufref3.Reserve(api);
        h_ar_bufref4.Reserve(api);
        h_ar_bufref5.Reserve(api);

        texbuf_init_det = apih.AMemoryGetPermanentT(api, [32]u8) orelse
            @panic("GAssetBuffer(init): API OutOfMemory(Patch)");
        texbuf_alloc = apih.AMemoryGetPermanentT(api, [TEXBUF_MAX_ITEMS]u32) orelse
            @panic("GAssetBuffer(init): API OutOfMemory(Items)");

        var d: x86.Detour = undefined;

        // TODO: this part probably not necessary, since reservation already
        //  asserts the handles were available
        const handles = [_]RAddressHandle{
            h_ar_detour.Handle,  h_ar_bufref1.Handle, h_ar_bufref2.Handle,
            h_ar_bufref3.Handle, h_ar_bufref4.Handle, h_ar_bufref5.Handle,
        };
        if (!apih.RAddressPatchToggleGroup(api, &handles, true)) return;

        // patch TextureBuffer_Init (fn_447420)
        if (s_texbuf_enable and api.RAddressRangeWriteSt(handles[0])) {
            defer api.RAddressRangeWriteEd(handles[0]);
            d.Start(0x447471, 0x44748D, texbuf_init_det);
            d.addr = x86.call(d.addr, @intFromPtr(&patch_texbuf));
            d.addr = x86.cdecl_call(d.addr, @intFromPtr(ra.Block_Close), &[_]x86.PushSrc{.{ .imm32 = 3 }});
            d.End();
        }
    }

    fn patch_texbuf() callconv(.C) void {
        const handles = [_]RAddressHandle{
            h_ar_bufref1.Handle, h_ar_bufref2.Handle, h_ar_bufref3.Handle,
            h_ar_bufref4.Handle, h_ar_bufref5.Handle,
        };

        if (!apih.RAddressPatchToggleGroup(api, &handles, true)) return;
        const tex_count: u32 = @min(TEXBUF_MAX_ITEMS, @max(@max(s_texbuf_size, @as(*u32, @ptrFromInt(0xE9823C)).*), 1700));

        // patch TextureBuffer_LoadModelTexture (fn_447490)
        _ = apih.RAddressRangeWrite(api, handles[0], 0x4474B1, u32, @intFromPtr(texbuf_alloc.ptr));
        _ = apih.RAddressRangeWrite(api, handles[1], 0x4474C4, u32, @intFromPtr(texbuf_alloc.ptr));
        _ = apih.RAddressRangeWrite(api, handles[2], 0x447555, u32, @intFromPtr(texbuf_alloc.ptr));
        // patch TextureBuffer_ClearBufferAfterPtr (fn_4475D0)
        _ = apih.RAddressRangeWrite(api, handles[3], 0x4475D5, u32, @intFromPtr(texbuf_alloc.ptr));
        _ = apih.RAddressRangeWrite(api, handles[4], 0x4475E7, u32, @intFromPtr(texbuf_alloc.ptr) + tex_count * 4);
    }

    fn settings_init() void {
        const section = api.ASettingSectionOccupy(SettingHandle.getNull(), "core/GAssetBuffer", null);
        h_s_section = section;

        h_s_texbuf_enable =
            api.ASettingOccupy(section, "texbuf_enable", .B, .{ .b = false }, &s_texbuf_enable, null);
        h_s_texbuf_size =
            api.ASettingOccupy(section, "texbuf_size", .U, .{ .u = 5120 }, &s_texbuf_size, null);
    }
};

// HOOKS

pub fn OnInit(gf: *GlobalFn) callconv(.C) void {
    // FIXME: don't do this
    GAssetBuffer.api = gf;

    GAssetBuffer.settings_init();
    GAssetBuffer.init();
}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {}
