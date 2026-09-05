// TODO: organize testing so that each submodule organizes its own tests, and
//  only the top-level modules are imported here (e.g. `@import("api/api.zig")`)
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
