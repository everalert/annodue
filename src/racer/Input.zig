const std = @import("std");

// TODO: get up to date with personal notes, update naming to match new understanding, finish cleanup, etc.
// TODO: add force feedback

//------------------------------------------------------------------------------
// GAME FUNCTIONS

pub const swrInput_ProcessInput: *fn () callconv(.C) void = @ptrFromInt(0x404DD0);
pub const swrInput_ReadControls: *fn () callconv(.C) void = @ptrFromInt(0x485630);
pub const swrInput_ReadKeyboard: *fn () callconv(.C) void = @ptrFromInt(0x486170);
pub const swrInput_ReadJoysticks: *fn () callconv(.C) void = @ptrFromInt(0x486340);
pub const swrInput_ReadMouse: *fn () callconv(.C) void = @ptrFromInt(0x486710);

//------------------------------------------------------------------------------
// GAME CONSTANTS

// FIXME: remove, old defs; convert refs here to 'unprocessed inputs' stuff below
pub const RAW_STATE_TIMESTAMP_ADDR: usize = 0x50E028;
pub const RAW_STATE_TIMESTAMP: *[0x210]u32 = @ptrFromInt(RAW_STATE_TIMESTAMP_ADDR);
pub const RAW_STATE_ON_ADDR: usize = 0x50E868;
pub const RAW_STATE_ON: *[0x210]u32 = @ptrFromInt(RAW_STATE_ON_ADDR);
pub const RAW_STATE_JUST_ON_ADDR: usize = 0x50F668;
pub const RAW_STATE_JUST_ON: *[0x210]u32 = @ptrFromInt(RAW_STATE_JUST_ON_ADDR);
// FIXME: end of block to remove

//--------------------------------------
// raw device inputs
// - written to directly from dinput api without modification

pub const JOYSTICK_DEVICE_COUNT: *u32 = @ptrFromInt(0x50FEC8);
pub const JOYSTICK_DEVICE_ACTIVE: *u32 = @ptrFromInt(0x4D6B3C);

//--------------------------------------
// unprocessed inputs
// - minimal mapping from dinput data

// TODO: proper characterization of button state addresses
pub const RAW_STATE_AXIS: *RAW_AXIS = @ptrFromInt(0x50D568);
pub const RAW_STATE_BUTTON_1: *RAW_BUTTON = @ptrFromInt(0x50E028); // durations in ms?
pub const RAW_STATE_BUTTON_2: *RAW_BUTTON = @ptrFromInt(0x50E868); // just on? on?
pub const RAW_STATE_BUTTON_3: *RAW_BUTTON = @ptrFromInt(0x50F668); // frames on?

// TODO: assert size 60*4
pub const RAW_AXIS = extern struct {
    Joystick: [48]f32, // 8 devices * 6 axes
    Mouse: [12]f32,
};

// TODO: assert size 0x210*4
pub const RAW_BUTTON = extern struct {
    Keyboard: [256]i32, // indexed via dinput scancodes (i.e. ascii scancodes)
    Joystick: [8]extern struct {
        Buttons: [16]i32,
        Hats: [4]extern struct {
            Left: i32,
            Up: i32,
            Right: i32,
            Down: i32,
        },
    },
    Mouse: [4]extern struct {
        Left: i32,
        Right: i32,
        Middle: i32,
        Back: i32,
    },
};

//--------------------------------------
// mapped inputs
// - converted to 'racer inputs' from 'unprocessed inputs' via control map

// TODO: 0xEC8820 (unk setup), 0xEC8880 (likely settings)
pub const MAPPED_BUTTON: *RaceInputs(BUTTON, u8) = @ptrFromInt(0xEC8810); // combined mapping
pub const MAPPED_AXIS: *RaceInputs(AXIS, f32) = @ptrFromInt(0xEC8830); // combined mapping
pub const MAPPED_BUTTON_F: *RaceInputs(BUTTON, f32) = @ptrFromInt(0xEC8840);
pub const MAPPED_BUTTON_F_HOLD_TIME: *RaceInputs(BUTTON, f32) = @ptrFromInt(0xEC88A0);

pub const MAP_BUTTON_TO_AXIS: *[16]u8 = @ptrFromInt(0x4B29D8); // b8; converting combined mapped buttons to axis

// TODO: collective race inputs struct typedef
// TODO: remove slice?
pub const MAPPED_BUTTON_DEVICE_JOYSTICK: *RaceInputs(BUTTON, f32) = @ptrFromInt(0x4D5E80);
pub const MAPPED_BUTTON_DEVICE_MOUSE: *RaceInputs(BUTTON, f32) = @ptrFromInt(0x4D5EBC);
pub const MAPPED_BUTTON_DEVICE_KEYBOARD: *RaceInputs(BUTTON, f32) = @ptrFromInt(0x4D5EF8);
pub const MAPPED_AXIS_DEVICE_JOYSTICK: *RaceInputs(AXIS, f32) = @ptrFromInt(0x4D5E30);
pub const MAPPED_AXIS_DEVICE_MOUSE: *RaceInputs(AXIS, f32) = @ptrFromInt(0x4D5E40);
pub const MAPPED_AXIS_DEVICE_KEYBOARD: *RaceInputs(AXIS, f32) = @ptrFromInt(0x4D5E50);

pub const CONFIG_COUNT_JOYSTICK: *i32 = @ptrFromInt(0x4D5E20);
pub const CONFIG_COUNT_MOUSE: *i32 = @ptrFromInt(0x4D5E24);
pub const CONFIG_COUNT_KEYBOARD: *i32 = @ptrFromInt(0x4D5E28);
pub const CONFIG_JOYSTICK: *[65]CONTROL_MAP = @ptrFromInt(0x4D5FC0);
pub const CONFIG_MOUSE: *[65]CONTROL_MAP = @ptrFromInt(0x4D6518);
pub const CONFIG_KEYBOARD: *[65]CONTROL_MAP = @ptrFromInt(0x4D6828);
pub const CONFIG_AXIS: *[60]AXIS_CONFIG = @ptrFromInt(0x50F0A8);

// FIXME: cleanup this section (BUTTON- and AXIS-related defs) with nicer naming and less fluff
pub const BUTTON_LENGTH: usize = 15;
pub const BUTTON_SIZE: usize = 16;
pub const BUTTON = enum(u8) { // TODO: typedef
    CameraCycle,
    CameraLookBack,
    Brake,
    Acceleration,
    Boost,
    Slide,
    TiltLeft,
    TiltRight,
    Taunt,
    Repair,
    Unk11,
    Unk12,
    Unk13,
    Unk14,
    Unk15,
};
pub const BUTTON_CAMERA_CYCLE: u8 = @intFromEnum(BUTTON.CameraCycle);
pub const BUTTON_CAMERA_LOOK_BACK: u8 = @intFromEnum(BUTTON.CameraLookBack);
pub const BUTTON_BRAKE: u8 = @intFromEnum(BUTTON.Brake);
pub const BUTTON_ACCELERATION: u8 = @intFromEnum(BUTTON.Acceleration);
pub const BUTTON_BOOST: u8 = @intFromEnum(BUTTON.Boost);
pub const BUTTON_SLIDE: u8 = @intFromEnum(BUTTON.Slide);
pub const BUTTON_TILT_LEFT: u8 = @intFromEnum(BUTTON.TiltLeft);
pub const BUTTON_TILT_RIGHT: u8 = @intFromEnum(BUTTON.TiltRight);
pub const BUTTON_TAUNT: u8 = @intFromEnum(BUTTON.Taunt);
pub const BUTTON_REPAIR: u8 = @intFromEnum(BUTTON.Repair);

pub const AXIS_LENGTH: usize = 4;
pub const AXIS_SIZE: usize = AXIS_LENGTH * 4;
pub const AXIS = enum(u8) { // TODO: typedef
    Thrust,
    Unk2, // NOTE: not analog brake; that results in digital brake output
    Steering,
    Pitch,
};
pub const AXIS_THRUST: u8 = @intFromEnum(AXIS.Thrust);
pub const AXIS_STEERING: u8 = @intFromEnum(AXIS.Steering);
pub const AXIS_PITCH: u8 = @intFromEnum(AXIS.Pitch);
// FIXME: end of cleanup section

pub fn RaceInputs(comptime E: type, comptime T: type) type {
    // TODO: assert E = enum
    // TODO: assert T = int, float
    return plugin: {
        const e = std.enums.values(E);
        var fields: [e.len]std.builtin.Type.StructField = undefined;

        for (e, 0..) |f, i| {
            fields[i] = .{
                .name = @tagName(f),
                .type = T,
                .default_value = null,
                .is_comptime = false,
                .alignment = 0,
            };
        }

        break :plugin @Type(.{ .Struct = .{
            .layout = .Extern,
            .fields = fields[0..],
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        } });
    };
}

// TODO: assert size 0x0C
pub const CONTROL_MAP = extern struct {
    Flags: CONTROL_MAP_FLAGS,
    InputIndex: i32, // translated to RAW_BUTTON offset
    OutputIndex: i32,
};

// TODO: assert size 0x0C
// associates FUNCTION in control map file with actual input
pub const CONTROL_MAP_DEF_FUNC = extern struct {
    OutputIndex: i32,
    FuncName: [*:0]const u8,
    DefaultFlags: CONTROL_MAP_FLAGS,
};

// TODO: assert size 0x08
// associates INPUT in control map file with actual input
pub const CONTROL_MAP_DEF_INPUT = extern struct {
    OutputIndex: i32,
    InputName: [*:0]const u8,
};

// TODO: assert size 32 bits
pub const CONTROL_MAP_FLAGS = packed struct {
    OutputAnalog: bool,
    OutputDigital: bool,
    InputAnalog: bool,
    InputDigital: bool,
    AnalogIsPositive: bool,
    AnalogIsNegative: bool,
    _06_31: u26, // unused
};

// TODO: assert size 0x18
pub const AXIS_CONFIG = extern struct {
    Flags: packed struct {
        Registered: bool,
        Enabled: bool,
        _02: bool,
        _03_ignore_deadzone: bool,
        _04_31: u28, // TODO: finalize
    },
    Min: i32,
    Max: i32,
    _0C_center: i32, // calibration offset
    Deadzone: i32,
    _14_sensitivity: f32,
};

//--------------------------------------
// packed inputs, i.e. 'racer inputs type 2'
// - converted from 'combined mapped inputs' into bitfield, via mapping input buffer

pub const PACKED: *INPUT_PACKED = @ptrFromInt(0xE98E80);

// filled out in ProcessInput before being packed into INPUT_BITFIELDs
pub const PACKING_BUFFER: *[4]INPUT_PACKING_BUFFER = @ptrFromInt(0xE98EE0);
pub const PACKING_BUFFER_MAP: *[16]i32 = @ptrFromInt(0x4B2998); // packing_btn[n] = mapped_btn[packing_map[n]]

// TODO: assert size 0x50
pub const INPUT_PACKED = extern struct {
    AxisY: [4]f32, // 0xE98E80
    ButtonRaw: *[4]INPUT_BITFIELD, // 0xE98E90
    AxisX: [4]f32, // 0xE98EA0
    ButtonJustOn: *[4]INPUT_BITFIELD, // 0xE98EB0
    ButtonJustOff: *[4]INPUT_BITFIELD, // 0xE98EC0
};

// TODO: assert size 0x18
pub const INPUT_PACKING_BUFFER = extern struct {
    AxisX: i16,
    AxisY: i16,
    Buttons: [16]u8,
    _14: i32, // may be unused
};

// TODO: separate into menu and race structs for different labels?
// TODO: testing assert size 32 bits
pub const INPUT_BITFIELD = packed struct {
    ACCELERATE: bool,
    BRAKE: bool,
    CAMERA_CYCLE: bool,
    CAMERA_LOOK_BACK: bool,
    TILT_LEFT: bool,
    TILT_RIGHT: bool,
    _06: bool,
    REPAIR: bool,
    SLIDE: bool,
    PAUSE: bool,
    _10_btn13: bool, // these 4 seem related to debug features
    _11_btn14: bool,
    _12_btn11: bool,
    _13_btn12: bool,
    AXIS_Y_UP: bool,
    AXIS_Y_DN: bool,
    AXIS_X_LF: bool,
    AXIS_X_RT: bool,
    AXIS_Y_N: bool,
    AXIS_X_N: bool,
    AXIS_X_LF_SOFT: bool,
    AXIS_X_RT_SOFT: bool,
    AXIS_Y_UP_SOFT: bool,
    AXIS_Y_DN_SOFT: bool,
    _24: bool, // seems to be unused bits, at least for menus; see fn_45A460
    _25: bool,
    _26: bool,
    _27: bool,
    _28: bool,
    _29: bool,
    _30: bool,
    _31: bool,
};

//--------------------------------------
// menu inputs
// - same as 'racer inputs type 2', but remapped specifically for menu (hang) use

pub const MENU_RAW: *[4]INPUT_BITFIELD = @ptrFromInt(0x50C908);
pub const MENU_JUST_ON: *[4]INPUT_BITFIELD = @ptrFromInt(0x50C918);
pub const MENU_AXIS_X: *[4]i32 = @ptrFromInt(0x50C970);
pub const MENU_AXIS_Y: *[4]i32 = @ptrFromInt(0x50C980);

//--------------------------------------
// misc

// multipliers for raw pitch input used on PC version only
pub const PITCH_SCALE_MAX: *f32 = @ptrFromInt(0x4AD8D8); // 0x3F4CCCCD (+0.8)
pub const PITCH_SCALE_MIN: *f32 = @ptrFromInt(0x4AD8DC); // 0xBF4CCCCD (-0.8)

//------------------------------------------------------------------------------
// HELPERS

// ...
