const std = @import("std");

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

pub const BUTTON_LENGTH: usize = 15;
pub const BUTTON_SIZE: usize = 16;
pub const BUTTON = enum(u8) { // TODO: typedef
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
                .default_value = 0,
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

// TODO: collective race inputs struct typedef
// TODO: remove slice?
pub const RACE_COMBINED_ADDR: usize = 0xEC8810;
pub const RACE_COMBINED_SIZE: usize = 0xD0;
pub const RACE_BUTTON_COMBINED_BASE_ADDR: usize = 0xEC8810;
pub const RACE_BUTTON_COMBINED: *RaceInputs(BUTTON, u8) = @ptrFromInt(RACE_BUTTON_COMBINED_BASE_ADDR);
pub const RACE_BUTTON_JOYSTICK_BASE_ADDR: usize = 0x4D5E80;
pub const RACE_BUTTON_JOYSTICK: *RaceInputs(BUTTON, f32) = @ptrFromInt(RACE_BUTTON_JOYSTICK_BASE_ADDR);
pub const RACE_BUTTON_MOUSE_BASE_ADDR: usize = 0x4D5EBC;
pub const RACE_BUTTON_MOUSE: *RaceInputs(BUTTON, f32) = @ptrFromInt(RACE_BUTTON_MOUSE_BASE_ADDR);
pub const RACE_BUTTON_KEYBOARD_BASE_ADDR: usize = 0x4D5EF8;
pub const RACE_BUTTON_KEYBOARD: *RaceInputs(BUTTON, f32) = @ptrFromInt(RACE_BUTTON_KEYBOARD_BASE_ADDR);
pub const RACE_AXIS_COMBINED_BASE_ADDR: usize = 0xEC8830;
pub const RACE_AXIS_COMBINED: *RaceInputs(AXIS, f32) = @ptrFromInt(RACE_AXIS_COMBINED_BASE_ADDR);
pub const RACE_AXIS_JOYSTICK_BASE_ADDR: usize = 0x4D5E30;
pub const RACE_AXIS_JOYSTICK: *RaceInputs(AXIS, f32) = @ptrFromInt(RACE_AXIS_JOYSTICK_BASE_ADDR);
pub const RACE_AXIS_MOUSE_BASE_ADDR: usize = 0x4D5E40;
pub const RACE_AXIS_MOUSE: *RaceInputs(AXIS, f32) = @ptrFromInt(RACE_AXIS_MOUSE_BASE_ADDR);
pub const RACE_AXIS_KEYBOARD_BASE_ADDR: usize = 0x4D5E50;
pub const RACE_AXIS_KEYBOARD: *RaceInputs(AXIS, f32) = @ptrFromInt(RACE_AXIS_KEYBOARD_BASE_ADDR);
pub const RACE_BUTTON_FLOAT_BASE_ADDR: usize = 0xEC8840;
pub const RACE_BUTTON_FLOAT: *RaceInputs(BUTTON, f32) = @ptrFromInt(RACE_BUTTON_FLOAT_BASE_ADDR);
pub const RACE_UNK_EC8880: usize = 0xEC8880; // likely settings
pub const RACE_BUTTON_FLOAT_HOLD_TIME_BASE_ADDR: usize = 0xEC88A0;
pub const RACE_BUTTON_FLOAT_HOLD_TIME: *RaceInputs(BUTTON, f32) = @ptrFromInt(RACE_BUTTON_FLOAT_HOLD_TIME_BASE_ADDR);

// TODO: global struct typedef
// TODO: bitfield typedef
// TODO: remove slice?
pub const GLOBAL_ADDR: usize = 0xE98E80;
pub const GLOBAL_SIZE: usize = 0x50;
pub const GLOBAL_AXIS_Y_ADDR: usize = 0xE98E80;
pub const GLOBAL_AXIS_Y: *[4]f32 = @ptrFromInt(GLOBAL_AXIS_Y_ADDR);
pub const GLOBAL_AXIS_X_ADDR: usize = 0xE98EA0;
pub const GLOBAL_AXIS_X: *[4]f32 = @ptrFromInt(GLOBAL_AXIS_X_ADDR);
pub const GLOBAL_BITFIELD_RAW_ADDR: usize = 0xE98E90;
pub const GLOBAL_BITFIELD_RAW: *[4]u32 = @ptrFromInt(GLOBAL_BITFIELD_RAW_ADDR);
pub const GLOBAL_BITFIELD_JUST_ON_ADDR: usize = 0xE98EB0;
pub const GLOBAL_BITFIELD_JUST_ON: *[4]u32 = @ptrFromInt(GLOBAL_BITFIELD_JUST_ON_ADDR);
pub const GLOBAL_BITFIELD_JUST_OFF_ADDR: usize = 0xE98EC0;
pub const GLOBAL_BITFIELD_JUST_OFF: *[4]u32 = @ptrFromInt(GLOBAL_BITFIELD_JUST_OFF_ADDR);

// HELPERS

// ...
