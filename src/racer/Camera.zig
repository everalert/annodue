const Vec3 = @import("Vector.zig").Vec3;
const Vec4 = @import("Vector.zig").Vec4;
const Mat4x3 = @import("Matrix.zig").Mat4x3;

// GAME FUNCTIONS

pub const swrCam_CamState_InitMainMat4: *fn (i: u16, val1: u16, mat4_ptr: usize, val2: u16) callconv(.C) void = @ptrFromInt(0x428A60);

pub const fnRdCamera_OrthoProject: *fn (out: ?[*]Vec3, in: ?[*]const Vec3) callconv(.C) void =
    @ptrFromInt(0x4900A0);
pub const fnRdCamera_OrthoProjectList: *fn (out: ?[*]Vec3, in: ?[*]const Vec3, count: i32) callconv(.C) void =
    @ptrFromInt(0x4900E0);
pub const fnRdCamera_OrthoProjectSquare: *fn (out: ?[*]Vec3, in: ?[*]const Vec3) callconv(.C) void =
    @ptrFromInt(0x490160);
pub const fnRdCamera_OrthoProjectSquareList: *fn (out: ?[*]Vec3, in: ?[*]const Vec3, count: i32) callconv(.C) void =
    @ptrFromInt(0x4901A0);
pub const fnRdCamera_PerspectiveProject: *fn (out: ?[*]Vec3, in: ?[*]const Vec3) callconv(.C) void =
    @ptrFromInt(0x490210);
pub const fnRdCamera_PerspectiveProjectList: *fn (out: ?[*]Vec3, in: ?[*]const Vec3, count: i32) callconv(.C) void =
    @ptrFromInt(0x490250);
pub const fnRdCamera_PerspectiveProjectSquare: *fn (out: ?[*]Vec3, in: ?[*]const Vec3) callconv(.C) void =
    @ptrFromInt(0x4902D0);
pub const fnRdCamera_PerspectiveProjectSquareList: *fn (out: ?[*]Vec3, in: ?[*]const Vec3, count: i32) callconv(.C) void =
    @ptrFromInt(0x490310);

// GAME CONSTANTS

pub const CameraViewMatrix: *Mat4x3 = @ptrFromInt(0xECC440);
pub const gRdCameraCurrent: *?*RD_CAMERA = @ptrFromInt(0xDF7F2C);

// TODO: typedef
// TODO: need a better name for this
pub const METACAM_ARRAY_ADDR: usize = 0xDFB040;
pub const METACAM_ARRAY_LEN: usize = 4;
pub const METACAM_ITEM_SIZE: usize = 0x16C;

// TODO: typedef
pub const CAMSTATE_ARRAY_ADDR: usize = 0xE9AA40;
pub const CAMSTATE_ARRAY_LEN: usize = 32;
pub const CAMSTATE_ITEM_SIZE: usize = 0x7C;

// GAME TYPEDEFS

// sizeof(0x878)
pub const RD_CAMERA = extern struct {
    _000_ProjectionType: u32,
    _004_pCanvas: ?*anyopaque, // *RD_CANVAS
    _008_ViewMatrix: Mat4x3,
    _038_FOV: f32,
    _03C_yFOV: f32,
    _040_AspectRatio: f32,
    _044_OrthoScale: f32,
    _048_pClipFrustum: ?*RD_CLIP_FRUSTUM,
    _04C_fnProject: ?*fn (out: ?[*]Vec3, in: ?[*]Vec3) callconv(.C) void,
    _050_fnProjectList: ?*fn (out: ?[*]Vec3, in: ?[*]Vec3, count: i32) callconv(.C) void,
    _054_AmbientLight: f32,
    _058: u32,
    _05C_ambient_light: Vec4,
    _06C_NumLights: i32,
    _070_apLights: [128]*Vec3,
    _270_LightPositions: [128]Vec3,
    _870_AttenuationMin: f32,
    _874_AttenuationMax: f32,
};

//sizeof(0x64)
pub const RD_CLIP_FRUSTUM = extern struct {
    _00_bFarClip: i32, // BOOL
    _04_ZNear: f32,
    _08_ZFar: f32,
    _0C_NearPlane: f32,
    _10_FarPlane: f32,
    _14_OrthoLeftPlane: f32,
    _18_OrthoTopPlane: f32,
    _1C_OrthoRightPlane: f32,
    _20_OrthoBottomPlane: f32,
    _24_TopPlane: f32,
    _28_BottomPlane: f32,
    _2C_LeftPlane: f32,
    _30_RightPlane: f32,
    _34_LeftPlaneNormal: Vec3,
    _40_RightPlaneNormal: Vec3,
    _4C_TopPlaneNormal: Vec3,
    _58_BottomPlaneNormal: Vec3,
};

// HELPERS

// ...
