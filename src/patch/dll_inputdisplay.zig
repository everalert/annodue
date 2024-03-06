pub const Self = @This();

const std = @import("std");
const m = std.math;

const GlobalState = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFn;
const COMPATIBILITY_VERSION = @import("global.zig").PLUGIN_VERSION;

const dbg = @import("util/debug.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const r = @import("util/racer.zig");
const rc = r.constants;
const rf = r.functions;

// TODO: robustness checking, particularly surrounding init and deinit for
// hotreloading case

// INPUT DISPLAY

const InputIcon = struct {
    bg_idx: ?u16,
    fg_idx: ?u16,
    x: i16,
    y: i16,
    w: i16,
    h: i16,
};

const InputDisplay = struct {
    var analog: [rc.INPUT_ANALOG_LENGTH]f32 = undefined;
    var digital: [rc.INPUT_DIGITAL_LENGTH]u8 = undefined;
    var p_triangle: ?u32 = null;
    var p_square: ?u32 = null;
    var icons: [12]InputIcon = undefined;
    const x_base: u16 = 420;
    const y_base: u16 = 432;

    fn ReadInputs() void {
        analog = mem.read(rc.INPUT_COMBINED_ANALOG_BASE_ADDR, @TypeOf(analog));
        digital = mem.read(rc.INPUT_COMBINED_DIGITAL_BASE_ADDR, @TypeOf(digital));
    }

    fn GetStick(input: rc.INPUT_ANALOG) f32 {
        return InputDisplay.analog[@intFromEnum(input)];
    }

    fn GetButton(input: rc.INPUT_DIGITAL) u8 {
        return InputDisplay.digital[@intFromEnum(input)];
    }

    fn UpdateIcons() void {
        UpdateIconSteering(&icons[0], &icons[1], .Steering);
        UpdateIconPitch(&icons[2], &icons[3], .Pitch);
        UpdateIconThrust(&icons[2 + rc.INPUT_DIGITAL_ACCELERATION], &icons[2 + rc.INPUT_DIGITAL_BRAKE], .Thrust, .Acceleration, .Brake);
        UpdateIconButton(&icons[2 + rc.INPUT_DIGITAL_BOOST], .Boost);
        UpdateIconButton(&icons[2 + rc.INPUT_DIGITAL_SLIDE], .Slide);
        UpdateIconButton(&icons[2 + rc.INPUT_DIGITAL_ROLL_LEFT], .RollLeft);
        UpdateIconButton(&icons[2 + rc.INPUT_DIGITAL_ROLL_RIGHT], .RollRight);
        //UpdateIconButton(&icons[2 + rc.INPUT_DIGITAL_TAUNT], .Taunt);
        UpdateIconButton(&icons[2 + rc.INPUT_DIGITAL_REPAIR], .Repair);
    }

    fn Init() void {
        p_triangle = rf.swrQuad_LoadTga("annodue/images/triangle_48x64.tga", 8001);
        p_square = rf.swrQuad_LoadSprite(26);
        InitIconSteering(&icons[0], &icons[1], x_base, y_base, 20);
        InitIconPitch(&icons[2], &icons[3], x_base + 44, y_base + 10, 2);
        InitIconThrust(&icons[2 + rc.INPUT_DIGITAL_ACCELERATION], &icons[2 + rc.INPUT_DIGITAL_BRAKE], x_base, y_base, 2);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_BOOST], x_base - 18, y_base + 19, 1, 1);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_SLIDE], x_base - 8, y_base + 19, 2, 1);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_ROLL_LEFT], x_base - 28, y_base + 19, 1, 1);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_ROLL_RIGHT], x_base + 20, y_base + 19, 1, 1);
        //InitIconButton(&icons[2 + rc.INPUT_DIGITAL_TAUNT], x_base, y_base, 1);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_REPAIR], x_base + 10, y_base + 19, 1, 1);
    }

    fn Deinit() void {
        for (&icons) |*icon| {
            if (icon.fg_idx) |i| {
                rf.swrQuad_SetActive(i, 0);
                icon.fg_idx = null;
            }
            if (icon.bg_idx) |i| {
                rf.swrQuad_SetActive(i, 0);
                icon.bg_idx = null;
            }
        }
        p_triangle = null;
        p_square = null;
    }

    fn HideAll() void {
        for (icons) |icon| {
            if (icon.bg_idx) |i| rf.swrQuad_SetActive(i, 0);
            if (icon.fg_idx) |i| rf.swrQuad_SetActive(i, 0);
        }
    }

    fn InitSingle(i: *?u16, spr: u32, x: i16, y: i16, xs: f32, ys: f32, bg: bool) void {
        i.* = r.InitNewQuad(spr);
        rf.swrQuad_SetFlags(i.*.?, 1 << 16);
        if (bg) rf.swrQuad_SetColor(i.*.?, 0x28, 0x28, 0x28, 0x80);
        if (!bg) rf.swrQuad_SetColor(i.*.?, 0x00, 0x00, 0x00, 0xFF);
        rf.swrQuad_SetPosition(i.*.?, x, y);
        rf.swrQuad_SetScale(i.*.?, xs, ys);
    }

    fn InitIconSteering(left: *InputIcon, right: *InputIcon, x: i16, y: i16, x_gap: i16) void {
        const scale: f32 = 0.5;

        left.x = x - 24 - @divFloor(x_gap, 2);
        left.y = y - 16;
        left.w = 24;
        left.h = 32;
        InitSingle(&left.fg_idx, p_triangle.?, left.x, left.y, scale, scale, false);
        InitSingle(&left.bg_idx, p_triangle.?, left.x, left.y, scale, scale, true);
        rf.swrQuad_SetFlags(left.fg_idx.?, 1 << 2 | 1 << 15);
        rf.swrQuad_SetFlags(left.bg_idx.?, 1 << 2 | 1 << 15);

        right.x = x + @divFloor(x_gap, 2);
        right.y = y - 16;
        right.w = 24;
        right.h = 32;
        InitSingle(&right.fg_idx, p_triangle.?, right.x, right.y, scale, scale, false);
        InitSingle(&right.bg_idx, p_triangle.?, right.x, right.y, scale, scale, true);
        rf.swrQuad_SetFlags(right.fg_idx.?, 1 << 15);
        rf.swrQuad_SetFlags(right.bg_idx.?, 1 << 15);
    }

    fn InitIconPitch(top: *InputIcon, bottom: *InputIcon, x: i16, y: i16, y_gap: i16) void {
        const x_scale: f32 = 1;
        const y_scale: f32 = 2;

        top.x = x - 4;
        top.y = y - 16 - @divFloor(y_gap, 2);
        top.w = 8;
        top.h = 16;
        InitSingle(&top.fg_idx, p_square.?, top.x, top.y, x_scale, y_scale, false);
        InitSingle(&top.bg_idx, p_square.?, top.x, top.y, x_scale, y_scale, true);
        rf.swrQuad_SetFlags(top.fg_idx.?, 1 << 15);
        rf.swrQuad_SetFlags(top.bg_idx.?, 1 << 15);

        bottom.x = x - 4;
        bottom.y = y + @divFloor(y_gap, 2);
        bottom.w = 8;
        bottom.h = 16;
        InitSingle(&bottom.fg_idx, p_square.?, bottom.x, bottom.y, x_scale, y_scale, false);
        InitSingle(&bottom.bg_idx, p_square.?, bottom.x, bottom.y, x_scale, y_scale, true);
        rf.swrQuad_SetFlags(bottom.fg_idx.?, 1 << 15);
        rf.swrQuad_SetFlags(bottom.bg_idx.?, 1 << 15);
    }

    fn InitIconThrust(accel: *InputIcon, brake: *InputIcon, x: i16, y: i16, y_gap: i16) void {
        const x_scale: f32 = 2;
        const y_scale: f32 = 2;

        accel.x = x - 8;
        accel.y = y - 16 - @divFloor(y_gap, 2);
        accel.w = 8;
        accel.h = 16;
        InitSingle(&accel.fg_idx, p_square.?, accel.x, accel.y, x_scale, y_scale, false);
        InitSingle(&accel.bg_idx, p_square.?, accel.x, accel.y, x_scale, y_scale, true);
        rf.swrQuad_SetFlags(accel.fg_idx.?, 1 << 15);
        rf.swrQuad_SetFlags(accel.bg_idx.?, 1 << 15);

        brake.x = x - 8;
        brake.y = y + @divFloor(y_gap, 2);
        brake.w = 8;
        brake.h = 16;
        InitSingle(&brake.fg_idx, p_square.?, brake.x, brake.y, x_scale, y_scale, false);
        InitSingle(&brake.bg_idx, p_square.?, brake.x, brake.y, x_scale, y_scale, true);
        rf.swrQuad_SetFlags(brake.fg_idx.?, 1 << 15);
        rf.swrQuad_SetFlags(brake.bg_idx.?, 1 << 15);
    }

    fn InitIconButton(i: *InputIcon, x: i16, y: i16, x_scale: f32, y_scale: f32) void {
        i.x = x;
        i.y = y;
        i.w = 8;
        i.h = 8;
        InitSingle(&i.fg_idx, p_square.?, i.x, i.y, x_scale, y_scale, false);
        InitSingle(&i.bg_idx, p_square.?, i.x, i.y, x_scale, y_scale, true);
    }

    fn UpdateIconSteering(left: *InputIcon, right: *InputIcon, input: rc.INPUT_ANALOG) void {
        const axis = InputDisplay.GetStick(input);
        const side = if (axis < 0) left else if (axis > 0) right else null;

        rf.swrQuad_SetActive(left.bg_idx.?, 1);
        rf.swrQuad_SetActive(left.fg_idx.?, 0);
        rf.swrQuad_SetActive(right.bg_idx.?, 1);
        rf.swrQuad_SetActive(right.fg_idx.?, 0);

        if (side) |s| {
            const pre: f32 = m.round(m.fabs(axis) * @as(f32, @floatFromInt(s.w)));
            const out: f32 = pre / @as(f32, @floatFromInt(s.w));
            rf.swrQuad_SetActive(s.fg_idx.?, 1);
            rf.swrQuad_SetScale(s.fg_idx.?, 0.5 * out, 0.5);
            if (axis < 0) {
                const off: i16 = s.w - @as(i16, @intFromFloat(pre));
                rf.swrQuad_SetPosition(s.fg_idx.?, s.x + off, s.y);
            }

            const text_xoff: u16 = 2;
            std.debug.assert(@divFloor(s.w, 2) >= text_xoff);
            var buf: [127:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&buf, "~F4~s~c{d:1.0}", .{
                std.math.fabs(axis * 100),
            }) catch unreachable;
            const txo: i16 = @divFloor(s.w, 2) - @as(i16, @intFromFloat(m.sign(axis) * text_xoff));
            rf.swrText_CreateEntry1(s.x + txo, s.y + @divFloor(s.h, 2) - 3, 255, 255, 255, 190, &buf);
        }
    }

    fn UpdateIconPitch(top: *InputIcon, bot: *InputIcon, input: rc.INPUT_ANALOG) void {
        const axis = InputDisplay.GetStick(input);
        const side = if (axis < 0) top else if (axis > 0) bot else null;

        rf.swrQuad_SetActive(top.bg_idx.?, 1);
        rf.swrQuad_SetActive(top.fg_idx.?, 0);
        rf.swrQuad_SetActive(bot.bg_idx.?, 1);
        rf.swrQuad_SetActive(bot.fg_idx.?, 0);

        if (side) |s| {
            const pre: f32 = m.round(m.fabs(axis) * @as(f32, @floatFromInt(s.h)));
            const out: f32 = pre / @as(f32, @floatFromInt(s.h));
            rf.swrQuad_SetActive(s.fg_idx.?, 1);
            rf.swrQuad_SetScale(s.fg_idx.?, 1, 2 * out);
            if (axis < 0) {
                const off: i16 = s.h - @as(i16, @intFromFloat(pre));
                rf.swrQuad_SetPosition(s.fg_idx.?, s.x, s.y + off);
            }

            const text_yoff: u16 = 5;
            std.debug.assert(s.h >= text_yoff);
            var buf: [127:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&buf, "~F4~s{d:1.0}", .{
                std.math.fabs(axis * 100),
            }) catch unreachable;
            const tyo: i16 = (if (axis < 0) s.h - text_yoff else text_yoff) - 3;
            rf.swrText_CreateEntry1(s.x + 2, s.y + tyo, 255, 255, 255, 190, &buf);
        }
    }

    fn UpdateIconThrust(top: *InputIcon, bot: *InputIcon, in_thrust: rc.INPUT_ANALOG, in_accel: rc.INPUT_DIGITAL, in_brake: rc.INPUT_DIGITAL) void {
        const thrust: f32 = InputDisplay.GetStick(in_thrust);
        const accel: bool = InputDisplay.GetButton(in_accel) > 0;
        const brake: bool = InputDisplay.GetButton(in_brake) > 0;
        const side = if (thrust < 0 and !accel) top else if (thrust > 0 and !brake) bot else null;
        _ = side;

        rf.swrQuad_SetActive(top.bg_idx.?, 1);
        rf.swrQuad_SetActive(top.fg_idx.?, 0);
        rf.swrQuad_SetActive(bot.bg_idx.?, 1);
        rf.swrQuad_SetActive(bot.fg_idx.?, 0);

        // NOTE: potentially add negative thrust vis to accel, maybe with color to differentiate
        if (accel) {
            rf.swrQuad_SetActive(top.bg_idx.?, 1);
            rf.swrQuad_SetActive(top.fg_idx.?, InputDisplay.digital[@intFromEnum(in_accel)]);
            rf.swrQuad_SetScale(top.fg_idx.?, 2, 2);
            rf.swrQuad_SetPosition(top.fg_idx.?, top.x, top.y);
        } else if (thrust > 0) {
            const pre: f32 = m.round(m.fabs(thrust) * @as(f32, @floatFromInt(top.h)));
            const out: f32 = pre / @as(f32, @floatFromInt(top.h));
            rf.swrQuad_SetActive(top.fg_idx.?, 1);
            rf.swrQuad_SetScale(top.fg_idx.?, 2, 2 * out);
            const off: i16 = top.h - @as(i16, @intFromFloat(pre));
            rf.swrQuad_SetPosition(top.fg_idx.?, top.x, top.y + off);
            if (thrust < 1) {
                var buf: [127:0]u8 = undefined;
                _ = std.fmt.bufPrintZ(&buf, "~F4~s~c{d:1.0}", .{
                    std.math.fabs(thrust * 100),
                }) catch unreachable;
                rf.swrText_CreateEntry1(top.x + 8, top.y - 8, 255, 255, 255, 190, &buf);
            }
        }
        if (brake) {
            rf.swrQuad_SetActive(bot.bg_idx.?, 1);
            rf.swrQuad_SetActive(bot.fg_idx.?, InputDisplay.digital[@intFromEnum(in_brake)]);
            rf.swrQuad_SetScale(bot.fg_idx.?, 2, 2);
            rf.swrQuad_SetPosition(bot.fg_idx.?, bot.x, bot.y);
        }
    }

    fn UpdateIconButton(i: *InputIcon, input: rc.INPUT_DIGITAL) void {
        rf.swrQuad_SetActive(i.bg_idx.?, 1);
        rf.swrQuad_SetActive(i.fg_idx.?, InputDisplay.digital[@intFromEnum(input)]);
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
    // if re-initialized during race
    if (gs.in_race.on() and !gs.player.in_race_results.on()) {
        InputDisplay.Init();
    }
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
    InputDisplay.Deinit();
}

// HOOK FUNCTIONS

export fn InitRaceQuadsA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    InputDisplay.Init();
}

export fn InputUpdateA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    if (gs.in_race.on()) {
        if (!gs.player.in_race_results.on()) {
            InputDisplay.ReadInputs();
            InputDisplay.UpdateIcons();
        } else {
            InputDisplay.HideAll();
        }
    }
}
