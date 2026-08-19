const std = @import("std");
const SemVer = std.SemanticVersion;

const SharedDef = @import("core/SharedDef.zig");
const AHook = @import("core/AHook.zig");
pub const GLOBAL_FUNCTION = SharedDef.GlobalFunction;
pub const COMPATIBILITY_VERSION =
    AHook.PLUGIN_FUNCTION_VERSION +
    SharedDef.GLOBAL_STATE_VERSION +
    SharedDef.GLOBAL_FUNCTION_VERSION +
    @import("core/GDraw.zig").GDRAW_VERSION;

pub const VERSION = SemVer{
    .major = 0,
    .minor = 1,
    .patch = 6,
    //.pre = "alpha",
    .build = "573",
};

pub const VERSION_MIN = SemVer{
    .major = 0,
    .minor = 1,
    .patch = 6,
    //.pre = "alpha",
};

// TODO: use SemanticVersion parse fn instead
// TODO: include tag when appropriate
pub const VERSION_STR: [:0]const u8 = std.fmt.comptimePrint(
    "Annodue {d}.{d}.{d}.{s}",
    .{
        VERSION.major,
        VERSION.minor,
        VERSION.patch,
        VERSION.build.?,
    },
);
