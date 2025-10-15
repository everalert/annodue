const std = @import("std");

const BOOL = std.os.windows.BOOL;
const FALSE = std.os.windows.FALSE;
const TRUE = std.os.windows.TRUE;

const assert = std.debug.assert;

// FIXME: lots of this belongs in different (new) files
// FIXME: ...including direct3d defs lol

// GAME TYPEDEFS

// FIXME: RGB bits per channel == ?
pub const ColorFormat = enum(u32) { RGB = 0, ARGB1555 = 1, ARGB4444 = 2 };

// SWR_MATERIAL
// sizeof(0x94)
pub const Material = extern struct {
    _00_Name: [64]u8, // NOTE: whole 0..63 range also sometimes used as string; union?
    //_0A_w_used_ratio: f32, // sometimes these offsets are used for something else
    //_0E_h_used_ratio: f32,
    _40_Num: i32,
    _44_ColorInfo: ColorInfo,
    _7C_ColorFormat: ColorFormat,
    _80_width: i32,
    _84_height: i32,
    _88_nbTextures: i32,
    _8C: i32,
    _90_paTextureAlloc: ?[*]SystemTexture,
};

// sizeof(0x94)
// SWR_SYSTEM_TEXTURE
pub const SystemTexture = extern struct {
    _00_DDSurfaceDesc: [0x7C]u8, // TODO: DDSURFACEDESC2 typedef
    _7C_pD3DTextureSrc: ?*anyopaque, // TODO: LPDIRECT3DTEXTURE2 typedef
    _80_pD3DTextureCached: ?*anyopaque, // TODO: LPDIRECT3DTEXTURE2 typedef
    _84_Size: i32,
    _88_Frames: i32,
    _8C_pPrev: ?*SystemTexture,
    _90_pNext: ?*SystemTexture,
};

// sizeof(0x60)
// STD_TEXTURE_FORMAT
pub const TextureFormat = extern struct {
    _00_ColorInfo: ColorInfo,
    _38_bColorKey: BOOL,
    _3C_pColorKey: ?*anyopaque, // TODO: (LP)DDCOLORKEY typedef
    _40_PixelFormat: [0x20]u8, // TODO: DDPIXELFORMAT typedef
};

// sizeof(0xE0)
// DISPLAY_TVBUFFER
pub const VBuffer = extern struct {
    _00_bSurfaceAllocated: BOOL,
    _04_LockSurfRefCount: i32,
    _08_bVideoMemory: BOOL,
    _0C_RasterInfo: RasterInfo,
    _58_pPixelData: ?[*]u16, // TODO: color format union;  expects 16-bit pixels
    _5C: i32,
    _60_Surface: VSurface,
};

// sizeof(0x80)
// DISPLAY_TVSURFACE
pub const VSurface = extern struct {
    _00_pDDSurface: ?*anyopaque, // TODO: (LP)DIRECTDRAWSURFACE4 typedef
    _04_DDSurfaceDesc: [0x7C]u8, // TODO: DDSURFACEDESC2 typedef
};

// sizeof(0x4C)
// DISPLAY_TRASTERINFO
pub const RasterInfo = extern struct {
    _00_Width: i32,
    _04_Height: i32,
    _08_Size: i32,
    _0C_RowSize: i32,
    _10_RowWidth: i32,
    _14_ColorInfo: ColorInfo,
};

// sizeof(0x38)
// SWR_COLOR_INFO
pub const ColorInfo = extern struct {
    _00_ColorFormat: ColorFormat,
    _04_BPP: i32,
    _08_BPPR: i32,
    _0C_BPPG: i32,
    _10_BPPB: i32,
    _14_PosShiftR: i32,
    _18_PosShiftG: i32,
    _1C_PosShiftB: i32,
    _20_ShrR: i32,
    _24_ShrG: i32,
    _28_ShrB: i32,
    _2C_BPPA: i32,
    _30_PosShiftA: i32,
    _34_ShrA: i32,
};

// sizeof(0x20)
pub const D3DTLVERTEX = extern struct {
    sx: f32,
    sy: f32,
    sz: f32,
    rhw: f32,
    color: u32, // 0xAARRGGBB
    specular: u32,
    tu: f32,
    tv: f32,
};

// GAME CONSTANTS

pub const aMaterialDefaultFilename: [*:0]const u8 = @ptrFromInt(0x4B48CC);
pub const aRovermatic: [*:0]const u8 = @ptrFromInt(0x4B48C0);

// GAME FUNCTIONS

pub const fn3DSceneBegin: *const fn () callconv(.C) void = @ptrFromInt(0x48A300);
pub const fn3DSceneEnd: *const fn () callconv(.C) void = @ptrFromInt(0x48A330);

pub const fn3DSetRenderState: *const fn (flags: u32) callconv(.C) void = @ptrFromInt(0x48A450);
pub const fn3DSetWireframeRenderState: *const fn () callconv(.C) void = @ptrFromInt(0x48A3C0);
pub const fn3DDrawTriangleList: *const fn (
    tex: ?*anyopaque, // *IDirect3DTexture2
    flags: u32,
    vtx: ?[*]const D3DTLVERTEX,
    vtx_count: i32,
    idx: ?[*]const i16,
    idx_count: i32,
) callconv(.C) void = @ptrFromInt(0x48A350);
pub const fn3DDrawLineStrip: *const fn (
    vtx: ?[*]const D3DTLVERTEX,
    vtx_count: u32,
) callconv(.C) void = @ptrFromInt(0x48A3F0);
pub const fn3DDrawPointList: *const fn (
    vtx: ?[*]const D3DTLVERTEX,
    vtx_count: u32,
) callconv(.C) void = @ptrFromInt(0x48A420);

pub const fn3DSetProjection: *const fn (hfov: f32, aspect: f32, znear: f32, zfar: f32) callconv(.C) void =
    @ptrFromInt(0x48B260);

pub const fn3DTextureAlloc: *const fn (
    tex: ?[*]SystemTexture,
    mip_buffers: ?[*]*VBuffer,
    mip_levels: u32,
    fmt: ColorFormat,
) callconv(.C) void =
    @ptrFromInt(0x48A5E0);

pub const fn3DTextureClear: *const fn (
    tex: ?[*]SystemTexture,
) callconv(.C) void =
    @ptrFromInt(0x48AA40);

pub const fnMaterialLoad: *const fn (path: ?[*:0]const u8) callconv(.C) ?*Material =
    @ptrFromInt(0x48E680);

pub const fnMaterialLoadEntry: *const fn (path: ?[*:0]const u8, mat: ?*Material) callconv(.C) BOOL =
    @ptrFromInt(0x48E6D0);

pub const fnMaterialFree: *const fn (mat: ?*Material) callconv(.C) BOOL =
    @ptrFromInt(0x48EAC0);

pub const fnMaterialFreeEntry: *const fn (mat: ?*Material) callconv(.C) BOOL =
    @ptrFromInt(0x48EB00);

pub const fnMaterialGetColorFormat: *const fn (info: ?*ColorInfo) callconv(.C) ColorFormat =
    @ptrFromInt(0x48A2D0);

// TODO: pKey type LPDDCOLORKEY
pub const fnMaterialPopulateColorKey: *const fn (
    fmt: ColorFormat,
    out_info: *ColorInfo,
    out_bKey: *BOOL,
    out_pKey: *anyopaque,
) callconv(.C) void = @ptrFromInt(0x48A230);

pub const fnDisplayVBufferNew: *const fn (
    info: ?*RasterInfo,
    bCreateDDSurface: BOOL,
    bUseVideoMemory: BOOL,
) callconv(.C) ?*VBuffer = @ptrFromInt(0x4881C0);

// FIXME: return value probably void? but marked int in ida for now
pub const fnDisplayVBufferFree: *const fn (?*VBuffer) callconv(.C) i32 = @ptrFromInt(0x488310);

// FIXME: unk return value meaning
pub const fnDisplayVBufferLock: *const fn (?*VBuffer) callconv(.C) i32 = @ptrFromInt(0x488370);

// FIXME: unk return value meaning
pub const fnDisplayVBufferUnlock: *const fn (?*VBuffer) callconv(.C) i32 = @ptrFromInt(0x4883C0);

pub const fnDisplayVBufferConvertColorFormat: *const fn (
    info: ?*ColorInfo,
    vbuf: ?*VBuffer,
    bKey: BOOL,
    pKey: ?*anyopaque,
) callconv(.C) ?*VBuffer = @ptrFromInt(0x488670);

pub const fn3DTextureGetFormatCount: *const fn () callconv(.C) u32 = @ptrFromInt(0x48A2F0);

// HELPERS

// FIXME: error handling for this and all the "owned" functions
pub fn hMaterial_OwnedNewFromData(
    data: []u16,
    w: i32, // dimensions of the pixel data buffer
    h: i32,
    w_used: i32, // dimensions actually covered by the texture
    h_used: i32,
    fmt: ColorFormat,
    out_tex: ?*SystemTexture,
    out_mat: ?*Material,
) void {
    hMaterial_OwnedNew(out_tex, out_mat, false);
    hMaterial_OwnedSetNewTexture(out_mat, data, w, h, w_used, h_used, fmt);
}

// based loosely on MaterialLoadEntry_48E6D0, but avoids any file interaction
// and minimizes allocations and instead pre-fills the data as it would be
// after using the above function to load it
// FIXME: uses ingame allocator via VBufferNew, VBufferFree; need to reimpl
// those too to completely remove dependence on game allocations
// TODO: make out_tex []SystemTexture, and duplicate default tex on all of them;
//   not urgent because nothing in the game actually uses this, just hypothetical
//   modding stuff
// TODO: write a string to out_mat name field (take string as input?)
pub fn hMaterial_OwnedNew(out_tex: ?*SystemTexture, out_mat: ?*Material, make_tex: bool) void {
    assert(out_tex != null);
    assert(out_mat != null);

    out_mat.?.* = std.mem.zeroes(Material);

    _ = std.fmt.bufPrint(&out_mat.?._00_Name, "{s}", .{aRovermatic}) catch
        unreachable; // FIXME: error handling
    var b_color_key: BOOL = undefined;
    var color_key: extern struct { low: i32, high: i32 } = undefined;
    var color_key_info: ColorInfo = undefined;
    @memcpy(@as([*]u8, @ptrCast(&out_mat.?._44_ColorInfo)), &default_mat_color_info);
    out_mat.?._7C_ColorFormat = fnMaterialGetColorFormat(&out_mat.?._44_ColorInfo);
    fnMaterialPopulateColorKey(out_mat.?._7C_ColorFormat, &color_key_info, &b_color_key, &color_key);

    out_mat.?._80_width = 16;
    out_mat.?._84_height = 16;

    out_mat.?._88_nbTextures = 1;
    out_mat.?._8C = 0;
    out_mat.?._90_paTextureAlloc = @ptrCast(out_tex.?);
    out_tex.?.* = std.mem.zeroes(SystemTexture);

    // generate surface with default texture
    // not needed if user will just immediately overwrite the texture
    if (!make_tex) return;

    var mip_raster_info = std.mem.zeroInit(RasterInfo, .{
        ._00_Width = 16,
        ._04_Height = 16,
        ._14_ColorInfo = out_mat.?._44_ColorInfo,
    });
    var mip_vbuffer = fnDisplayVBufferNew(&mip_raster_info, 0, 0);
    defer _ = fnDisplayVBufferFree(mip_vbuffer);

    _ = fnDisplayVBufferLock(mip_vbuffer);
    @memcpy(@as([*]u8, @ptrCast(mip_vbuffer.?._58_pPixelData.?)), &default_mat_pixel_data);
    _ = fnDisplayVBufferUnlock(mip_vbuffer);

    if (mip_vbuffer.?._0C_RasterInfo._14_ColorInfo._00_ColorFormat != .RGB and
        fn3DTextureGetFormatCount() > 0)
    {
        mip_vbuffer = fnDisplayVBufferConvertColorFormat(&color_key_info, mip_vbuffer, b_color_key, &color_key);
    }

    var mip_vbuf_p = [1]*VBuffer{mip_vbuffer.?};
    fn3DTextureAlloc(out_mat.?._90_paTextureAlloc, &mip_vbuf_p, 1, out_mat.?._7C_ColorFormat);
}

// counterpart to Material_OwnedNew; based on Model_MaterialFreeEntry__48EB00,
// but assumes the material has only one texture and that the user will dispose
// of that themself (because we are freeing something from OwnedNew)
// WARN: indirectly makes reference to cached textures, not sure if that actually
// comes up in our usecase
pub fn hMaterial_OwnedFree(mat: ?*Material) void {
    assert(mat != null);
    fn3DTextureClear(mat.?._90_paTextureAlloc);
}

// based loosely on fn_445EE0 as an easier way to just generate a material from
// a pixel buffer.  mainly differs in that the game's asset buffer is not used,
// and that it takes a pre-encoded pixel buffer instead doing the conversion
pub fn hMaterial_OwnedSetNewTexture(
    mat: ?*Material,
    data: []u16,
    w: i32, // dimensions of the pixel data buffer
    h: i32,
    w_used: i32, // dimensions actually covered by the texture
    h_used: i32,
    fmt: ColorFormat,
) void {
    assert(fmt == .ARGB4444 or fmt == .ARGB1555);
    assert(w >= w_used);
    assert(h >= h_used);
    assert(data.len == w * h);

    hMaterial_SetFormat(mat.?, fmt);
    _ = std.fmt.bufPrint(&mat.?._00_Name, "{s}", .{aRovermatic}) catch unreachable; // FIXME: error handling
    // NOTE: workaround until fixing typedef
    //mat._0A_w_used_ratio
    @as(*align(1) f32, @ptrCast(&mat.?._00_Name[10])).* =
        @as(f32, @floatFromInt(w_used)) / @as(f32, @floatFromInt(w));
    //mat._0E_h_used_ratio
    @as(*align(1) f32, @ptrCast(&mat.?._00_Name[14])).* =
        @as(f32, @floatFromInt(h_used)) / @as(f32, @floatFromInt(h));
    mat.?._40_Num = 0;
    mat.?._80_width = w;
    mat.?._84_height = h;
    mat.?._88_nbTextures = 1;
    mat.?._8C = 0;

    var vbuf = VBuffer{
        ._00_bSurfaceAllocated = FALSE,
        ._04_LockSurfRefCount = 0,
        ._08_bVideoMemory = FALSE,
        ._0C_RasterInfo = RasterInfo{
            ._00_Width = w,
            ._04_Height = h,
            ._08_Size = 2 * w * h,
            ._0C_RowSize = 2 * w,
            ._10_RowWidth = w,
            ._14_ColorInfo = mat.?._44_ColorInfo,
        },
        ._5C = 0,
        ._58_pPixelData = data.ptr,
        ._60_Surface = undefined,
    };

    var vbuf_p = [1]*VBuffer{&vbuf};
    fn3DTextureClear(mat.?._90_paTextureAlloc);
    fn3DTextureAlloc(mat.?._90_paTextureAlloc, &vbuf_p, 1, fmt);
}

pub fn hMaterial_SetFormat(mat: *Material, fmt: ColorFormat) void {
    assert(fmt != .RGB); // unsupported for now
    switch (fmt) {
        .ARGB1555 => {
            mat._7C_ColorFormat = .ARGB1555;
            mat._44_ColorInfo = .{
                ._00_ColorFormat = .ARGB1555,
                ._04_BPP = 16,
                ._08_BPPR = 5,
                ._0C_BPPG = 5,
                ._10_BPPB = 5,
                ._14_PosShiftR = 11,
                ._18_PosShiftG = 6,
                ._1C_PosShiftB = 1,
                ._20_ShrR = 3,
                ._24_ShrG = 3,
                ._28_ShrB = 3,
                ._2C_BPPA = 1,
                ._30_PosShiftA = 0,
                ._34_ShrA = 7,
            };
        },
        .ARGB4444 => {
            mat._7C_ColorFormat = .ARGB4444;
            mat._44_ColorInfo = .{
                ._00_ColorFormat = .ARGB4444,
                ._04_BPP = 16,
                ._08_BPPR = 4,
                ._0C_BPPG = 4,
                ._10_BPPB = 4,
                ._14_PosShiftR = 12,
                ._18_PosShiftG = 8,
                ._1C_PosShiftB = 4,
                ._20_ShrR = 4,
                ._24_ShrG = 4,
                ._28_ShrB = 4,
                ._2C_BPPA = 4,
                ._30_PosShiftA = 0,
                ._34_ShrA = 4,
            };
        },
        else => unreachable,
    }
}

const default_mat_color_info = [_]u8{
    0x01, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00,
    0x06, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x0B, 0x00, 0x00, 0x00,
    0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00,
    0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

// 16x16 u16
const default_mat_pixel_data = [_]u8{
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x88, 0xF6, 0xC4, 0xFB, 0xC4, 0xFB, 0x06, 0xF5,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x86, 0xFC,
    0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0x41, 0xF9, 0x09, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x88, 0xF6, 0x00, 0xF8, 0x00, 0xF8, 0x43, 0xFA,
    0x44, 0xFB, 0x40, 0xF8, 0x00, 0xF8, 0x44, 0xFB, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x05, 0xFC, 0x00, 0xF8, 0xC1, 0xF8, 0x89, 0xF7, 0x89, 0xF7, 0x44, 0xFB,
    0x00, 0xF8, 0xC2, 0xF9, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x88, 0xF6,
    0x07, 0xF6, 0x89, 0xF7, 0x89, 0xF7, 0x44, 0xFB, 0x00, 0xF8, 0xC3, 0xFA,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x07, 0xF6, 0x40, 0xF8, 0x00, 0xF8, 0x87, 0xF5, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x07, 0xF6, 0x40, 0xF8, 0x00, 0xF8,
    0xC3, 0xFA, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x07, 0xF6, 0x40, 0xF8, 0x00, 0xF8, 0xC3, 0xFA, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x09, 0xF7, 0x40, 0xF8, 0x00, 0xF8,
    0xC3, 0xFA, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x41, 0xF9, 0x00, 0xF8, 0x41, 0xF9, 0x87, 0xF5, 0x87, 0xF5,
    0x87, 0xF5, 0x07, 0xF6, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x86, 0xF4, 0x00, 0xF8,
    0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0xC2, 0xF9,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x43, 0xFA, 0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8,
    0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0xC2, 0xF9, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
    0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7, 0x89, 0xF7,
};
