const std = @import("std");
const SemVer = std.SemanticVersion;

pub const Plugin = @import("plugin/plugin.zig");
pub const PluginAPI = Plugin.PluginAPI;
pub const PLUGIN_API_VERSION = Plugin.PLUGIN_API_VERSION;

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

// TODO: organize testing so that each submodule organizes its own tests, and
//  only the top-level modules are imported here (e.g. `@import("plugin/plugin.zig")`)
test {
    _ = @import("gif.zig");
    _ = @import("png.zig");
    _ = @import("color_format.zig");

    _ = @import("handle_map.zig");
    _ = @import("handle_map_soa.zig");
    _ = @import("handle_map_static.zig");

    _ = @import("temporal_compression.zig");
    _ = @import("toggle_state.zig");

    _ = @import("xinput.zig");

    _ = @import("memory.zig");
    _ = @import("x86.zig");

    _ = @import("base/base_arena.zig");
    _ = @import("base/base_memory.zig");
    _ = @import("base/base_math.zig");

    _ = @import("core/core_address.zig");
}
