pub const Self = @This();

const std = @import("std");
const m = std.math;

const GlobalSt = @import("appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const nt = @import("util/normalized_transform.zig");
const dbg = @import("util/debug.zig");
const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");

const rg = @import("racer").Global;
const rq = @import("racer").Quad;
const rt = @import("racer").Text;
const ri = @import("racer").Input;
const rto = rt.TextStyleOpts;

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FEATURES
// - Visualize inputs during race
// - Shows inputs as they are after the game finishes device read merging and post-processing
// - SETTINGS:
//   * game considers screen to be 640x480 regardless of window size
//   enable     bool
//   pos_x      i32
//   pos_y      i32

// TODO: robustness checking, particularly surrounding init and deinit for
// hotreloading case
// TODO: restyling, esp. adding color and maybe redo sprites (rounded?)
// TODO: finalize representing negative thrust case

const PLUGIN_NAME: [*:0]const u8 = "InputDisplay";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

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
    var enable: bool = false;
    var initialized: bool = false;
    var analog: [ri.AXIS_LENGTH]f32 = undefined;
    var digital: [ri.BUTTON_LENGTH]u8 = undefined;
    var p_triangle: ?*rq.Sprite = null;
    var p_square: ?*rq.Sprite = null;
    var icons: [12]InputIcon = undefined;
    var x_base: i16 = 420;
    var y_base: i16 = 432;
    const style_center = rt.MakeTextHeadStyle(.Small, true, null, .Center, .{rto.ToggleShadow}) catch "";
    const style_left = rt.MakeTextHeadStyle(.Small, true, null, null, .{rto.ToggleShadow}) catch "";

    fn ReadInputs() void {
        analog = mem.read(ri.RACE_AXIS_COMBINED_BASE_ADDR, @TypeOf(analog));
        digital = mem.read(ri.RACE_BUTTON_COMBINED_BASE_ADDR, @TypeOf(digital));
    }

    fn GetStick(input: ri.AXIS) f32 {
        return InputDisplay.analog[@intFromEnum(input)];
    }

    fn GetButton(input: ri.BUTTON) u8 {
        return InputDisplay.digital[@intFromEnum(input)];
    }

    fn UpdateIcons(gf: *GlobalFn) void {
        UpdateIconSteering(gf, &icons[0], &icons[1], .Steering);
        UpdateIconPitch(gf, &icons[2], &icons[3], .Pitch);
        UpdateIconThrust(gf, &icons[2 + ri.BUTTON_ACCELERATION], &icons[2 + ri.BUTTON_BRAKE], .Thrust, .Acceleration, .Brake);
        UpdateIconButton(&icons[2 + ri.BUTTON_BOOST], .Boost);
        UpdateIconButton(&icons[2 + ri.BUTTON_SLIDE], .Slide);
        UpdateIconButton(&icons[2 + ri.BUTTON_ROLL_LEFT], .RollLeft);
        UpdateIconButton(&icons[2 + ri.BUTTON_ROLL_RIGHT], .RollRight);
        //UpdateIconButton(&icons[2 + ri.BUTTON_TAUNT], .Taunt);
        UpdateIconButton(&icons[2 + ri.BUTTON_REPAIR], .Repair);
    }

    fn Init() void {
        p_triangle = rq.swrQuad_LoadTga("annodue/images/triangle_48x64.tga", 8001);
        p_square = rq.swrQuad_LoadSprite(26);
        InitIconSteering(&icons[0], &icons[1], x_base, y_base, 20);
        InitIconPitch(&icons[2], &icons[3], x_base + 44, y_base + 10, 2);
        InitIconThrust(&icons[2 + ri.BUTTON_ACCELERATION], &icons[2 + ri.BUTTON_BRAKE], x_base, y_base, 2);
        InitIconButton(&icons[2 + ri.BUTTON_BOOST], x_base - 18, y_base + 19, 1, 1);
        InitIconButton(&icons[2 + ri.BUTTON_SLIDE], x_base - 8, y_base + 19, 2, 1);
        InitIconButton(&icons[2 + ri.BUTTON_ROLL_LEFT], x_base - 28, y_base + 19, 1, 1);
        InitIconButton(&icons[2 + ri.BUTTON_ROLL_RIGHT], x_base + 20, y_base + 19, 1, 1);
        //InitIconButton(&icons[2 + ri.BUTTON_TAUNT], x_base, y_base, 1);
        InitIconButton(&icons[2 + ri.BUTTON_REPAIR], x_base + 10, y_base + 19, 1, 1);

        initialized = true;
    }

    fn Deinit() void {
        for (&icons) |*icon| {
            if (icon.fg_idx) |i| {
                rq.swrQuad_SetActive(i, 0);
                icon.fg_idx = null;
            }
            if (icon.bg_idx) |i| {
                rq.swrQuad_SetActive(i, 0);
                icon.bg_idx = null;
            }
        }
        p_triangle = null;
        p_square = null;

        initialized = false;
    }

    fn HideAll() void {
        for (icons) |icon| {
            if (icon.bg_idx) |i| rq.swrQuad_SetActive(i, 0);
            if (icon.fg_idx) |i| rq.swrQuad_SetActive(i, 0);
        }
    }

    fn SetOpacityAll(a: f32) void {
        const a_bg: u8 = @intFromFloat(nt.pow2(a) * 127);
        const a_fg: u8 = @intFromFloat(nt.pow2(a) * 255);
        for (icons) |icon| {
            if (icon.bg_idx) |i| rq.swrQuad_SetColor(i, 0x28, 0x28, 0x28, a_bg);
            if (icon.fg_idx) |i| rq.swrQuad_SetColor(i, 0x00, 0x00, 0x00, a_fg);
        }
    }

    fn InitSingle(i: *?u16, spr: *rq.Sprite, x: i16, y: i16, xs: f32, ys: f32, bg: bool) void {
        i.* = rq.InitNewQuad(spr) catch return; // FIXME: actual error handling
        rq.swrQuad_SetFlags(i.*.?, 1 << 16);
        if (bg) rq.swrQuad_SetColor(i.*.?, 0x28, 0x28, 0x28, 0x80);
        if (!bg) rq.swrQuad_SetColor(i.*.?, 0x00, 0x00, 0x00, 0xFF);
        rq.swrQuad_SetPosition(i.*.?, x, y);
        rq.swrQuad_SetScale(i.*.?, xs, ys);
    }

    fn InitIconSteering(left: *InputIcon, right: *InputIcon, x: i16, y: i16, x_gap: i16) void {
        const scale: f32 = 0.5;

        left.x = x - 24 - @divFloor(x_gap, 2);
        left.y = y - 16;
        left.w = 24;
        left.h = 32;
        InitSingle(&left.fg_idx, p_triangle.?, left.x, left.y, scale, scale, false);
        InitSingle(&left.bg_idx, p_triangle.?, left.x, left.y, scale, scale, true);
        rq.swrQuad_SetFlags(left.fg_idx.?, 1 << 2 | 1 << 15);
        rq.swrQuad_SetFlags(left.bg_idx.?, 1 << 2 | 1 << 15);

        right.x = x + @divFloor(x_gap, 2);
        right.y = y - 16;
        right.w = 24;
        right.h = 32;
        InitSingle(&right.fg_idx, p_triangle.?, right.x, right.y, scale, scale, false);
        InitSingle(&right.bg_idx, p_triangle.?, right.x, right.y, scale, scale, true);
        rq.swrQuad_SetFlags(right.fg_idx.?, 1 << 15);
        rq.swrQuad_SetFlags(right.bg_idx.?, 1 << 15);
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
        rq.swrQuad_SetFlags(top.fg_idx.?, 1 << 15);
        rq.swrQuad_SetFlags(top.bg_idx.?, 1 << 15);

        bottom.x = x - 4;
        bottom.y = y + @divFloor(y_gap, 2);
        bottom.w = 8;
        bottom.h = 16;
        InitSingle(&bottom.fg_idx, p_square.?, bottom.x, bottom.y, x_scale, y_scale, false);
        InitSingle(&bottom.bg_idx, p_square.?, bottom.x, bottom.y, x_scale, y_scale, true);
        rq.swrQuad_SetFlags(bottom.fg_idx.?, 1 << 15);
        rq.swrQuad_SetFlags(bottom.bg_idx.?, 1 << 15);
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
        rq.swrQuad_SetFlags(accel.fg_idx.?, 1 << 15);
        rq.swrQuad_SetFlags(accel.bg_idx.?, 1 << 15);

        brake.x = x - 8;
        brake.y = y + @divFloor(y_gap, 2);
        brake.w = 8;
        brake.h = 16;
        InitSingle(&brake.fg_idx, p_square.?, brake.x, brake.y, x_scale, y_scale, false);
        InitSingle(&brake.bg_idx, p_square.?, brake.x, brake.y, x_scale, y_scale, true);
        rq.swrQuad_SetFlags(brake.fg_idx.?, 1 << 15);
        rq.swrQuad_SetFlags(brake.bg_idx.?, 1 << 15);
    }

    fn InitIconButton(i: *InputIcon, x: i16, y: i16, x_scale: f32, y_scale: f32) void {
        i.x = x;
        i.y = y;
        i.w = 8;
        i.h = 8;
        InitSingle(&i.fg_idx, p_square.?, i.x, i.y, x_scale, y_scale, false);
        InitSingle(&i.bg_idx, p_square.?, i.x, i.y, x_scale, y_scale, true);
    }

    fn UpdateIconSteering(gf: *GlobalFn, left: *InputIcon, right: *InputIcon, input: ri.AXIS) void {
        const axis = InputDisplay.GetStick(input);
        const side = if (axis < 0) left else if (axis > 0) right else null;

        rq.swrQuad_SetActive(left.bg_idx.?, 1);
        rq.swrQuad_SetActive(left.fg_idx.?, 0);
        rq.swrQuad_SetActive(right.bg_idx.?, 1);
        rq.swrQuad_SetActive(right.fg_idx.?, 0);

        if (side) |s| {
            const pre: f32 = m.round(m.fabs(axis) * @as(f32, @floatFromInt(s.w)));
            const out: f32 = pre / @as(f32, @floatFromInt(s.w));
            rq.swrQuad_SetActive(s.fg_idx.?, 1);
            rq.swrQuad_SetScale(s.fg_idx.?, 0.5 * out, 0.5);
            if (axis < 0) {
                const off: i16 = s.w - @as(i16, @intFromFloat(pre));
                rq.swrQuad_SetPosition(s.fg_idx.?, s.x + off, s.y);
            }

            const text_xoff: u16 = 2;
            std.debug.assert(@divFloor(s.w, 2) >= text_xoff);
            const txo: i16 = @divFloor(s.w, 2) - @as(i16, @intFromFloat(m.sign(axis) * text_xoff));
            const col: u32 = 0xFFFFFF00 |
                @as(u32, @intFromFloat(nt.pow2(1 - rg.PAUSE_SCROLLINOUT.*) * 255));
            _ = gf.GDrawText(
                .Default,
                rt.MakeText(s.x + txo, s.y + @divFloor(s.h, 2) - 3, "{d:1.0}", .{
                    std.math.fabs(axis * 100),
                }, col, style_center) catch null,
            );
        }
    }

    fn UpdateIconPitch(gf: *GlobalFn, top: *InputIcon, bot: *InputIcon, input: ri.AXIS) void {
        const axis = InputDisplay.GetStick(input);
        const side = if (axis < 0) top else if (axis > 0) bot else null;

        rq.swrQuad_SetActive(top.bg_idx.?, 1);
        rq.swrQuad_SetActive(top.fg_idx.?, 0);
        rq.swrQuad_SetActive(bot.bg_idx.?, 1);
        rq.swrQuad_SetActive(bot.fg_idx.?, 0);

        if (side) |s| {
            const pre: f32 = m.round(m.fabs(axis) * @as(f32, @floatFromInt(s.h)));
            const out: f32 = pre / @as(f32, @floatFromInt(s.h));
            rq.swrQuad_SetActive(s.fg_idx.?, 1);
            rq.swrQuad_SetScale(s.fg_idx.?, 1, 2 * out);
            if (axis < 0) {
                const off: i16 = s.h - @as(i16, @intFromFloat(pre));
                rq.swrQuad_SetPosition(s.fg_idx.?, s.x, s.y + off);
            }

            const text_yoff: u16 = 5;
            std.debug.assert(s.h >= text_yoff);
            const tyo: i16 = (if (axis < 0) s.h - text_yoff else text_yoff) - 3;
            const col: u32 = 0xFFFFFF00 |
                @as(u32, @intFromFloat(nt.pow2(1 - rg.PAUSE_SCROLLINOUT.*) * 255));
            _ = gf.GDrawText(
                .Default,
                rt.MakeText(s.x + 2, s.y + tyo, "{d:1.0}", .{
                    std.math.fabs(axis * 100),
                }, col, style_left) catch null,
            );
        }
    }

    fn UpdateIconThrust(gf: *GlobalFn, top: *InputIcon, bot: *InputIcon, in_thrust: ri.AXIS, in_accel: ri.BUTTON, in_brake: ri.BUTTON) void {
        const thrust: f32 = InputDisplay.GetStick(in_thrust);
        const accel: bool = InputDisplay.GetButton(in_accel) > 0;
        const brake: bool = InputDisplay.GetButton(in_brake) > 0;
        const side = if (thrust < 0 and !accel) top else if (thrust > 0 and !brake) bot else null;
        _ = side;

        rq.swrQuad_SetActive(top.bg_idx.?, 1);
        rq.swrQuad_SetActive(top.fg_idx.?, 0);
        rq.swrQuad_SetActive(bot.bg_idx.?, 1);
        rq.swrQuad_SetActive(bot.fg_idx.?, 0);

        // NOTE: potentially add negative thrust vis to accel, maybe with color to differentiate
        if (accel) {
            rq.swrQuad_SetActive(top.bg_idx.?, 1);
            rq.swrQuad_SetActive(top.fg_idx.?, InputDisplay.digital[@intFromEnum(in_accel)]);
            rq.swrQuad_SetScale(top.fg_idx.?, 2, 2);
            rq.swrQuad_SetPosition(top.fg_idx.?, top.x, top.y);
        } else if (thrust > 0) {
            const pre: f32 = m.round(m.fabs(thrust) * @as(f32, @floatFromInt(top.h)));
            const out: f32 = pre / @as(f32, @floatFromInt(top.h));
            rq.swrQuad_SetActive(top.fg_idx.?, 1);
            rq.swrQuad_SetScale(top.fg_idx.?, 2, 2 * out);
            const off: i16 = top.h - @as(i16, @intFromFloat(pre));
            rq.swrQuad_SetPosition(top.fg_idx.?, top.x, top.y + off);
            if (thrust < 1) {
                const col: u32 = 0xFFFFFF00 |
                    @as(u32, @intFromFloat(nt.pow2(1 - rg.PAUSE_SCROLLINOUT.*) * 255));
                _ = gf.GDrawText(
                    .Default,
                    rt.MakeText(top.x + 8, top.y - 8, "{d:1.0}", .{
                        std.math.fabs(thrust * 100),
                    }, col, style_center) catch null,
                );
            }
        }
        if (brake) {
            rq.swrQuad_SetActive(bot.bg_idx.?, 1);
            rq.swrQuad_SetActive(bot.fg_idx.?, InputDisplay.digital[@intFromEnum(in_brake)]);
            rq.swrQuad_SetScale(bot.fg_idx.?, 2, 2);
            rq.swrQuad_SetPosition(bot.fg_idx.?, bot.x, bot.y);
        }
    }

    fn UpdateIconButton(i: *InputIcon, input: ri.BUTTON) void {
        rq.swrQuad_SetActive(i.bg_idx.?, 1);
        rq.swrQuad_SetActive(i.fg_idx.?, InputDisplay.digital[@intFromEnum(input)]);
    }

    // TODO: handle updating position without having to reload race
    fn HandleSettings(gf: *GlobalFn) callconv(.C) void {
        enable = gf.SettingGetB("inputdisplay", "enable") orelse false;
        if (gf.SettingGetI("inputdisplay", "pos_x")) |x| x_base = @as(i16, @truncate(x));
        if (gf.SettingGetI("inputdisplay", "pos_y")) |y| y_base = @as(i16, @truncate(y));
    }
};

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
    InputDisplay.HandleSettings(gf);

    if ((gs.race_state == .Countdown or gs.race_state == .Racing) and InputDisplay.enable)
        InputDisplay.Init();
}

export fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    InputDisplay.Deinit();
}

// HOOK FUNCTIONS

export fn OnSettingsLoad(_: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    InputDisplay.HandleSettings(gf);
}

export fn InitRaceQuadsA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    if (InputDisplay.enable)
        InputDisplay.Init();
}

// TODO: probably cleaner with a state machine
//export fn InputUpdateA(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
export fn Draw2DB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (gs.in_race.on()) {
        if (InputDisplay.enable and !InputDisplay.initialized)
            InputDisplay.Init();

        if (InputDisplay.enable and
            InputDisplay.initialized and
            rg.PAUSE_STATE.* != 1 and
            !gf.GHideRaceUIIsHidden() and
            (gs.race_state == .Countdown or gs.race_state == .Racing))
        {
            const a: f32 = 1 - rg.PAUSE_SCROLLINOUT.*;
            InputDisplay.ReadInputs();
            InputDisplay.UpdateIcons(gf);
            InputDisplay.SetOpacityAll(a);
        } else {
            InputDisplay.HideAll();
        }
    } else if (gs.in_race == .JustOff) {
        InputDisplay.initialized = false;
    }
}
