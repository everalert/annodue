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

// INPUT DISPLAY

const InputIcon = struct {
    bg_idx: u16,
    fg_idx: u16,
    x: u16,
    y: u16,
    w: u16,
    h: u16,
};

const InputDisplay = struct {
    var analog: [rc.INPUT_ANALOG_LENGTH]f32 = undefined;
    var digital: [rc.INPUT_DIGITAL_LENGTH]u8 = undefined;
    var p_triangle: u32 = undefined;
    var p_square: u32 = undefined;
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
        UpdateIconButton(&icons[2 + rc.INPUT_DIGITAL_BRAKE], .Brake);
        UpdateIconButton(&icons[2 + rc.INPUT_DIGITAL_ACCELERATION], .Acceleration);
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
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_BRAKE], x_base - 8, y_base + 1, 2, 2);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_ACCELERATION], x_base - 8, y_base - 17, 2, 2);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_BOOST], x_base - 18, y_base + 19, 1, 1);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_SLIDE], x_base - 8, y_base + 19, 2, 1);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_ROLL_LEFT], x_base - 28, y_base + 19, 1, 1);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_ROLL_RIGHT], x_base + 20, y_base + 19, 1, 1);
        //InitIconButton(&icons[2 + rc.INPUT_DIGITAL_TAUNT], x_base, y_base, 1);
        InitIconButton(&icons[2 + rc.INPUT_DIGITAL_REPAIR], x_base + 10, y_base + 19, 1, 1);
    }

    fn InitSingle(i: *u16, spr: u32, x: u16, y: u16, xs: f32, ys: f32, bg: bool) void {
        i.* = r.InitNewQuad(spr);
        rf.swrQuad_SetFlags(i.*, 1 << 16);
        if (bg) rf.swrQuad_SetColor(i.*, 0x28, 0x28, 0x28, 0x80);
        if (!bg) rf.swrQuad_SetColor(i.*, 0x00, 0x00, 0x00, 0xFF);
        rf.swrQuad_SetPosition(i.*, x, y);
        rf.swrQuad_SetScale(i.*, xs, ys);
    }

    fn InitIconSteering(left: *InputIcon, right: *InputIcon, x: u16, y: u16, x_gap: u16) void {
        const scale: f32 = 0.5;

        left.x = x - 24 - x_gap / 2;
        left.y = y - 16;
        left.w = 24;
        left.h = 32;
        InitSingle(&left.fg_idx, p_triangle, left.x, left.y, scale, scale, false);
        InitSingle(&left.bg_idx, p_triangle, left.x, left.y, scale, scale, true);
        rf.swrQuad_SetFlags(left.fg_idx, 1 << 2 | 1 << 15);
        rf.swrQuad_SetFlags(left.bg_idx, 1 << 2 | 1 << 15);

        right.x = x + x_gap / 2;
        right.y = y - 16;
        right.w = 24;
        right.h = 32;
        InitSingle(&right.fg_idx, p_triangle, right.x, right.y, scale, scale, false);
        InitSingle(&right.bg_idx, p_triangle, right.x, right.y, scale, scale, true);
        rf.swrQuad_SetFlags(right.fg_idx, 1 << 15);
        rf.swrQuad_SetFlags(right.bg_idx, 1 << 15);
    }

    fn InitIconPitch(top: *InputIcon, bottom: *InputIcon, x: u16, y: u16, y_gap: u16) void {
        const x_scale: f32 = 1;
        const y_scale: f32 = 2;

        top.x = x - 4;
        top.y = y - 16 - y_gap / 2;
        top.w = 8;
        top.h = 16;
        InitSingle(&top.fg_idx, p_square, top.x, top.y, x_scale, y_scale, false);
        InitSingle(&top.bg_idx, p_square, top.x, top.y, x_scale, y_scale, true);
        rf.swrQuad_SetFlags(top.fg_idx, 1 << 15);
        rf.swrQuad_SetFlags(top.bg_idx, 1 << 15);

        bottom.x = x - 4;
        bottom.y = y + y_gap / 2;
        bottom.w = 8;
        bottom.h = 16;
        InitSingle(&bottom.fg_idx, p_square, bottom.x, bottom.y, x_scale, y_scale, false);
        InitSingle(&bottom.bg_idx, p_square, bottom.x, bottom.y, x_scale, y_scale, true);
        rf.swrQuad_SetFlags(bottom.fg_idx, 1 << 15);
        rf.swrQuad_SetFlags(bottom.bg_idx, 1 << 15);
    }

    fn InitIconButton(i: *InputIcon, x: u16, y: u16, x_scale: f32, y_scale: f32) void {
        i.x = x;
        i.y = y;
        i.w = 8;
        i.h = 8;
        InitSingle(&i.fg_idx, p_square, i.x, i.y, x_scale, y_scale, false);
        InitSingle(&i.bg_idx, p_square, i.x, i.y, x_scale, y_scale, true);
    }

    fn UpdateIconSteering(left: *InputIcon, right: *InputIcon, input: rc.INPUT_ANALOG) void {
        const axis = InputDisplay.GetStick(input);
        const side = if (axis < 0) left else if (axis > 0) right else null;

        rf.swrQuad_SetActive(left.bg_idx, 1);
        rf.swrQuad_SetActive(left.fg_idx, 0);
        rf.swrQuad_SetActive(right.bg_idx, 1);
        rf.swrQuad_SetActive(right.fg_idx, 0);

        if (side) |s| {
            const pre: f32 = m.round(m.fabs(axis) * @as(f32, @floatFromInt(s.w)));
            const out: f32 = pre / @as(f32, @floatFromInt(s.w));
            rf.swrQuad_SetActive(s.fg_idx, 1);
            rf.swrQuad_SetScale(s.fg_idx, 0.5 * out, 0.5);
            if (axis < 0) {
                const off: u16 = s.w - @as(u16, @intFromFloat(pre));
                rf.swrQuad_SetPosition(s.fg_idx, s.x + off, s.y);
            }

            var buf: [127:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&buf, "~F0~s~c{d:1.0}", .{
                std.math.fabs(axis * 100),
            }) catch unreachable;
            rf.swrText_CreateEntry1(s.x + s.w / 2, s.y + s.h / 3 * 2, 255, 255, 255, 190, &buf);
        }
    }

    fn UpdateIconPitch(top: *InputIcon, bottom: *InputIcon, input: rc.INPUT_ANALOG) void {
        const axis = InputDisplay.GetStick(input);
        const side = if (axis < 0) top else if (axis > 0) bottom else null;

        rf.swrQuad_SetActive(top.bg_idx, 1);
        rf.swrQuad_SetActive(top.fg_idx, 0);
        rf.swrQuad_SetActive(bottom.bg_idx, 1);
        rf.swrQuad_SetActive(bottom.fg_idx, 0);

        if (side) |s| {
            const pre: f32 = m.round(m.fabs(axis) * @as(f32, @floatFromInt(s.h)));
            const out: f32 = pre / @as(f32, @floatFromInt(s.h));
            rf.swrQuad_SetActive(s.fg_idx, 1);
            rf.swrQuad_SetScale(s.fg_idx, 1, 2 * out);
            if (axis < 0) {
                const off: u16 = s.h - @as(u16, @intFromFloat(pre));
                rf.swrQuad_SetPosition(s.fg_idx, s.x, s.y + off);
            }

            var buf: [127:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&buf, "~F0~s{d:1.0}", .{
                std.math.fabs(axis * 100),
            }) catch unreachable;
            rf.swrText_CreateEntry1(s.x + 2, s.y + s.h / 2 - 4, 255, 255, 255, 190, &buf);
        }
    }

    fn UpdateIconButton(i: *InputIcon, input: rc.INPUT_DIGITAL) void {
        rf.swrQuad_SetActive(i.bg_idx, 1);
        rf.swrQuad_SetActive(i.fg_idx, InputDisplay.digital[@intFromEnum(input)]);
    }

    fn HideAll() void {
        for (icons) |icon| {
            rf.swrQuad_SetActive(icon.bg_idx, 0);
            rf.swrQuad_SetActive(icon.fg_idx, 0);
        }
    }
};

// PRACTICE MODE VIS

const mode_vis = struct {
    const scale: f32 = 0.35;
    const x_rt: u16 = 640 - @round(32 * scale);
    const y_bt: u16 = 480 - @round(32 * scale);
    var spr: u32 = undefined;
    var tl: u16 = undefined;
    var tr: u16 = undefined;
    var bl: u16 = undefined;
    var br: u16 = undefined;

    fn init() void {
        spr = rf.swrQuad_LoadTga("annodue/images/corner_round_32.tga", 8000);
        init_single(&tl, false, false);
        init_single(&tr, false, true);
        init_single(&bl, true, false);
        init_single(&br, true, true);
    }

    fn init_single(id: *u16, bt: bool, rt: bool) void {
        id.* = r.InitNewQuad(spr);
        rf.swrQuad_SetFlags(id.*, 1 << 15 | 1 << 16);
        if (rt) rf.swrQuad_SetFlags(id.*, 1 << 2);
        if (!bt) rf.swrQuad_SetFlags(id.*, 1 << 3);
        rf.swrQuad_SetColor(id.*, 0xFF, 0xFF, 0x9C, 0xFF);
        rf.swrQuad_SetPosition(id.*, if (rt) x_rt else 0, if (bt) y_bt else 0);
        rf.swrQuad_SetScale(id.*, scale, scale);
    }

    //swrQuad_LoadSprite: *fn (i: u32) callconv(.C) u32 = @ptrFromInt(0x446FB0);
    fn update(active: bool, cr: u8, cg: u8, cb: u8) void {
        rf.swrQuad_SetActive(tl, @intFromBool(active));
        rf.swrQuad_SetActive(tr, @intFromBool(active));
        rf.swrQuad_SetActive(bl, @intFromBool(active));
        rf.swrQuad_SetActive(br, @intFromBool(active));
        if (active) {
            rf.swrQuad_SetColor(tl, cr, cg, cb, 0xFF);
            rf.swrQuad_SetColor(tr, cr, cg, cb, 0xFF);
            rf.swrQuad_SetColor(bl, cr, cg, cb, 0xFF);
            rf.swrQuad_SetColor(br, cr, cg, cb, 0xFF);
        }
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

export fn InitRaceQuadsA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    InputDisplay.Init();
}

export fn InputUpdateA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    if (gs.in_race.isOn()) {
        if (!gs.player.in_race_results.isOn()) {
            InputDisplay.ReadInputs();
            InputDisplay.UpdateIcons();

            //var buf: [127:0]u8 = undefined;
            //_ = std.fmt.bufPrintZ(&buf, "~F0~s~c{d:0>3.0} {d:0>3.0} {d}{d}{d}{d}{d}{d}{d}{d}", .{
            //    std.math.fabs(InputDisplay.GetStick(.Steering) * 100),
            //    std.math.fabs(InputDisplay.GetStick(.Pitch) * 100),
            //    InputDisplay.GetButton(.Brake),
            //    InputDisplay.GetButton(.Acceleration),
            //    InputDisplay.GetButton(.Boost),
            //    InputDisplay.GetButton(.Slide),
            //    InputDisplay.GetButton(.RollLeft),
            //    InputDisplay.GetButton(.RollRight),
            //    InputDisplay.GetButton(.Taunt),
            //    InputDisplay.GetButton(.Repair),
            //}) catch unreachable;
            //rf.swrText_CreateEntry1(320, 480 - 16, 255, 255, 255, 190, &buf);
        } else {
            InputDisplay.HideAll();
        }
    }
}
