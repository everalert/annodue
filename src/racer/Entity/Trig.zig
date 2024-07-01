const std = @import("std");
const BOOL = std.os.windows.BOOL;

const e = @import("entity.zig");
const Test = e.Test.Test;

// GAME FUNCTIONS

pub const HandleTriggers: *fn (*Trig, *Test, is_local: BOOL) callconv(.C) void = @ptrFromInt(0x47CE60);

pub const fnStage14: *fn (*Trig) callconv(.C) void = @ptrFromInt(0x47C390);
//pub const fnStage18: *fn (*Trig) callconv(.C) void = @ptrFromInt(0x00);
pub const fnStage1C: *fn (*Trig) callconv(.C) void = @ptrFromInt(0x47C500);
//pub const fnStage20: *fn (*Trig) callconv(.C) void = @ptrFromInt(0x00);
pub const fnEvent: *fn (*Trig, magic: *e.MAGIC_EVENT, payload: u32) callconv(.C) void = @ptrFromInt(0x47C710);

// GAME CONSTANTS

// ...

// GAME TYPEDEFS

pub const SIZE: usize = e.EntitySize(.Trig);

pub const Trig = extern struct {
    entity_magic: u32,
    entity_flags: u32,
    _unk_000_END: [SIZE - 8]u8,
};

// HELPERS

// ...
