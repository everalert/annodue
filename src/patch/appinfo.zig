const std = @import("std");
const SemVer = std.SemanticVersion;

const shared = @import("core/SharedDef.zig");
pub const GLOBAL_STATE = shared.GlobalState;
pub const GLOBAL_FUNCTION = shared.GlobalFunction;
pub const COMPATIBILITY_VERSION =
    shared.GLOBAL_STATE_VERSION +
    shared.GLOBAL_FUNCTION_VERSION +
    @import("core/GDraw.zig").GDRAW_VERSION;

pub const VERSION = SemVer{
    .major = 0,
    .minor = 1,
    .patch = 6,
    //.pre = "alpha",
    .build = "573",
};

// TODO: re-evaluate; '-autoupdate' suffix added in 0.1.6, but '-update' still checked for
pub const VERSION_MIN = SemVer{
    .major = 0,
    .minor = 1,
    .patch = 2,
    //.pre = "alpha",
};

// TODO: use SemanticVersion parse fn instead
// TODO: include tag when appropriate
pub const VERSION_STR: [:0]u8 = s: {
    var buf: [127:0]u8 = undefined;
    break :s std.fmt.bufPrintZ(&buf, "Annodue {d}.{d}.{d}.{s}", .{
        VERSION.major,
        VERSION.minor,
        VERSION.patch,
        VERSION.build.?,
    }) catch unreachable; // comptime
};
