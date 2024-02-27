pub const Self = @This();

const std = @import("std");

const GlobalState = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFn;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const dbg = @import("util/debug.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const r = @import("util/racer.zig");
const rc = r.constants;
const rf = r.functions;

// INPUT DISPLAY

const InputDisplay = struct {
    var analog: [rc.INPUT_ANALOG_LENGTH]f32 = undefined;
    var digital: [rc.INPUT_DIGITAL_LENGTH]u8 = undefined;

    fn Update() void {
        analog = mem.read(rc.INPUT_COMBINED_ANALOG_BASE_ADDR, @TypeOf(analog));
        digital = mem.read(rc.INPUT_COMBINED_DIGITAL_BASE_ADDR, @TypeOf(digital));
    }

    fn GetStick(input: rc.INPUT_ANALOG) f32 {
        return InputDisplay.analog[@intFromEnum(input)];
    }

    fn GetButton(input: rc.INPUT_DIGITAL) u8 {
        return InputDisplay.digital[@intFromEnum(input)];
    }
};

// HOUSEKEEPING

export fn PluginName() callconv(.C) [*:0]const u8 {
    return "InputDisplay";
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return "0.0.1";
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

export fn OnInit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnInitLate(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

export fn OnDeinit(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
}

// HOOK FUNCTIONS

export fn InputUpdateA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    if (gs.in_race.isOn() and !gs.player.in_race_results.isOn()) {
        var buf: [127:0]u8 = undefined;

        InputDisplay.Update();

        _ = std.fmt.bufPrintZ(&buf, "~F0~s~c{d:0>3.0} {d:0>3.0} {d}{d}{d}{d}{d}{d}{d}{d}", .{
            std.math.fabs(InputDisplay.GetStick(.Steering) * 100),
            std.math.fabs(InputDisplay.GetStick(.Pitch) * 100),
            InputDisplay.GetButton(.Brake),
            InputDisplay.GetButton(.Acceleration),
            InputDisplay.GetButton(.Boost),
            InputDisplay.GetButton(.Slide),
            InputDisplay.GetButton(.RollLeft),
            InputDisplay.GetButton(.RollRight),
            InputDisplay.GetButton(.Taunt),
            InputDisplay.GetButton(.Repair),
        }) catch unreachable;
        rf.swrText_CreateEntry1(320, 480 - 16, 255, 255, 255, 190, &buf);
    }
}
