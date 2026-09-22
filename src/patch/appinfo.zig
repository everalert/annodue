const PLUGIN_API_VERSION = @import("util/plugin/plugin_api.zig").PLUGIN_API_VERSION;
const DRAW_VERSION = @import("util/core/core_draw.zig").DRAW_VERSION;
const SharedDef = @import("core/SharedDef.zig");
const AHook = @import("core/AHook.zig");

pub const COMPATIBILITY_VERSION =
    AHook.PLUGIN_FUNCTION_VERSION +
    SharedDef.GLOBAL_STATE_VERSION +
    PLUGIN_API_VERSION +
    DRAW_VERSION;

pub const VERSION = @import("util/root.zig").VERSION;
pub const VERSION_MIN = @import("util/root.zig").VERSION_MIN;
pub const VERSION_STR = @import("util/root.zig").VERSION_STR;
