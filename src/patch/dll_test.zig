const Self = @This();

const std = @import("std");

const GlobalSt = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFunction;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;
const VERSION_STR = @import("global.zig").VersionStr;

const msg = @import("util/message.zig");
const r = @import("util/racer.zig");
const rf = r.functions;
const rc = r.constants;
const rt = r.text;
const rto = rt.TextStyleOpts;

// FEATURES
// -
// - CONTROLS:      keyboard        xinput
//   ..             ..              ..
// - SETTINGS:
//   ..             type    note

const PLUGIN_NAME: [*:0]const u8 = "PluginTest";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return PLUGIN_NAME;
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return PLUGIN_VERSION;
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

export fn OnInitLate(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;
}

// HOOKS

export fn EarlyEngineUpdateA(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    _ = gf;
    _ = gs;

    //rt.DrawText(16, 16, "{s} {s}", .{
    //    PLUGIN_NAME,
    //    PLUGIN_VERSION,
    //}, null, null) catch {};
}

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub fn panic(message: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    msg.Message("{s} {s}", .{ PLUGIN_NAME, PLUGIN_VERSION }, "PANIC AT THE DISCO", .{});
    std.builtin.default_panic(message, error_return_trace, ret_addr);
}
