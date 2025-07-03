const std = @import("std");

const BOOL = std.os.windows.BOOL;
const FALSE = std.os.windows.FALSE;
const TRUE = std.os.windows.TRUE;

const assert = std.debug.assert;

// FIXME: lots of this belongs in different (new) files

// GAME TYPEDEFS

// FIXME: RGB bits per channel == ?
pub const ColorFormat = enum(u32) { RGB = 0, RGBA5551 = 1, RGBA4444 = 2 };

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

// GAME CONSTANTS

pub const aMaterialDefaultFilename: [*:0]const u8 = @ptrFromInt(0x4B48CC);
pub const aRovermatic: [*:0]const u8 = @ptrFromInt(0x4B48C0);

// GAME FUNCTIONS

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

// HELPERS

// based loosely on fn_445EE0 as an easier way to just generate a material from
// a pixel buffer.  mainly differs in that the game's asset buffer is not used,
// and that it takes a pre-encoded pixel buffer instead doing the conversion
// FIXME: uses ingame allocator, convert to user-provided alloc or buffer
pub fn hMaterial_CreateFromTextureData(
    data: []u16,
    w: i32, // dimensions of the pixel data buffer
    h: i32,
    w_used: i32, // dimensions actually covered by the texture
    h_used: i32,
    fmt: ColorFormat,
) ?*Material {
    assert(fmt == .RGBA4444 or fmt == .RGBA5551);
    assert(w >= w_used);
    assert(h >= h_used);
    assert(data.len == w * h);

    var mat: *Material = fnMaterialLoad(aMaterialDefaultFilename) orelse return null;
    errdefer fnMaterialFree(mat);

    hMaterial_SetFormat(mat, fmt);
    _ = std.fmt.bufPrint(&mat._00_Name, "{s}", .{aRovermatic}) catch unreachable; // FIXME: error handling
    // NOTE: workaround until fixing typedef
    //mat._0A_w_used_ratio
    @as(*align(1) f32, @ptrCast(&mat._00_Name[10])).* =
        @as(f32, @floatFromInt(w_used)) / @as(f32, @floatFromInt(w));
    //mat._0E_h_used_ratio
    @as(*align(1) f32, @ptrCast(&mat._00_Name[14])).* =
        @as(f32, @floatFromInt(h_used)) / @as(f32, @floatFromInt(h));
    mat._40_Num = 0;
    mat._80_width = w;
    mat._84_height = h;
    mat._88_nbTextures = 1;
    mat._8C = 0;

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
            ._14_ColorInfo = mat._44_ColorInfo,
        },
        ._5C = 0,
        ._58_pPixelData = data.ptr,
        ._60_Surface = undefined,
    };

    var vbuf_p = [1]*VBuffer{&vbuf};
    fn3DTextureClear(mat._90_paTextureAlloc);
    fn3DTextureAlloc(mat._90_paTextureAlloc, &vbuf_p, 1, fmt);

    return mat;
}

// counterpart to Material_CreateFromTextureData
// FIXME: uses ingame allocator, convert to user-provided alloc or buffer
pub fn hMaterial_Free(mat: ?*Material) void {
    assert(mat != null);
    fn3DTextureClear(mat.?._90_paTextureAlloc);
    _ = fnMaterialFree(mat);
}

pub fn hMaterial_SetFormat(mat: *Material, fmt: ColorFormat) void {
    assert(fmt != .RGB); // unsupported for now
    switch (fmt) {
        .RGBA5551 => {
            mat._7C_ColorFormat = .RGBA5551;
            mat._44_ColorInfo = .{
                ._00_ColorFormat = .RGBA5551,
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
        .RGBA4444 => {
            mat._7C_ColorFormat = .RGBA4444;
            mat._44_ColorInfo = .{
                ._00_ColorFormat = .RGBA4444,
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
