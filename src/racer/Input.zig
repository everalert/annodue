// GAME FUNCTIONS

pub const swrInput_ProcessInput: *fn () callconv(.C) void = @ptrFromInt(0x404DD0);
pub const swrInput_ReadControls: *fn () callconv(.C) void = @ptrFromInt(0x485630);
pub const swrInput_ReadKeyboard: *fn () callconv(.C) void = @ptrFromInt(0x486170);
pub const swrInput_ReadJoysticks: *fn () callconv(.C) void = @ptrFromInt(0x486340);
pub const swrInput_ReadMouse: *fn () callconv(.C) void = @ptrFromInt(0x486710);

// GAME CONSTANTS

pub const RAW_STATE_TIMESTAMP: usize = 0x50E028;
pub const RAW_STATE_ON: usize = 0x50E868;
pub const RAW_STATE_JUST_ON: usize = 0x50F668;

pub const COMBINED_ADDR: usize = 0xEC8810;
pub const COMBINED_SIZE: usize = 0x30;

pub const AXIS_LENGTH: usize = 4;
pub const AXIS_SIZE: usize = AXIS_LENGTH * 4;
pub const AXIS_COMBINED_BASE_ADDR: usize = 0xEC8830;
pub const AXIS_JOYSTICK_BASE_ADDR: usize = 0x4D5E30;
pub const AXIS_MOUSE_BASE_ADDR: usize = 0x4D5E40;
pub const AXIS_KEYBOARD_BASE_ADDR: usize = 0x4D5E50;

// TODO: convert to typedef; same for button
pub const AXIS = enum(u8) {
    Thrust,
    Unk2, // NOTE: not analog brake; that results in digital brake output
    Steering,
    Pitch,
};
pub const AXIS_STEERING: u8 = @intFromEnum(AXIS.Steering);
pub const AXIS_PITCH: u8 = @intFromEnum(AXIS.Pitch);

pub const BUTTON_LENGTH: usize = 15;
pub const BUTTON_SIZE: usize = 16;
pub const BUTTON_COMBINED_BASE_ADDR: usize = 0xEC8810;
pub const BUTTON_JOYSTICK_BASE_ADDR: usize = 0x4D5E80;
pub const BUTTON_MOUSE_BASE_ADDR: usize = 0x4D5EBC;
pub const BUTTON_KEYBOARD_BASE_ADDR: usize = 0x4D5EF8;

pub const BUTTON = enum(u8) {
    Camera,
    LookBack,
    Brake,
    Acceleration,
    Boost,
    Slide,
    RollLeft,
    RollRight,
    Taunt,
    Repair,
    Unk11,
    Unk12,
    Unk13,
    Unk14,
    Unk15,
};
pub const BUTTON_CAMERA: u8 = @intFromEnum(BUTTON.Camera);
pub const BUTTON_LOOK_BACK: u8 = @intFromEnum(BUTTON.LookBack);
pub const BUTTON_BRAKE: u8 = @intFromEnum(BUTTON.Brake);
pub const BUTTON_ACCELERATION: u8 = @intFromEnum(BUTTON.Acceleration);
pub const BUTTON_BOOST: u8 = @intFromEnum(BUTTON.Boost);
pub const BUTTON_SLIDE: u8 = @intFromEnum(BUTTON.Slide);
pub const BUTTON_ROLL_LEFT: u8 = @intFromEnum(BUTTON.RollLeft);
pub const BUTTON_ROLL_RIGHT: u8 = @intFromEnum(BUTTON.RollRight);
pub const BUTTON_TAUNT: u8 = @intFromEnum(BUTTON.Taunt);
pub const BUTTON_REPAIR: u8 = @intFromEnum(BUTTON.Repair);

// HELPERS

// ...
