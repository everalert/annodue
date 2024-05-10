pub const Self = @This();

const std = @import("std");

const s = @import("Settings.zig").state;
const GlobalSt = @import("Global.zig").GlobalState;
const GlobalFn = @import("Global.zig").GlobalFunction;

const fl = @import("../util/flash.zig");
const st = @import("../util/active_state.zig");
const nt = @import("../util/normalized_transform.zig");
const mem = @import("../util/memory.zig");

const r = @import("../util/racer.zig");
const rf = @import("racer").functions;
const rc = @import("racer").constants;
const rt = @import("racer").text;
const rto = rt.TextStyleOpts;

// FIXME: refactor and merge with core
// TODO: allow toggling mode at any time (during race), but only update the visualization
// in a "more legit" direction when outside a race; e.g. if you switch from practice mode
// to play mode during a race, the system will still indicate that it's in practice mode
// until you exit the race or restart, BUT if you go in the direction of play -> practice,
// the visualization will update immediately
// also, same concept for anticheat stuff

// PRACTICE MODE VISUALIZATION

const mode_vis = struct {
    const x_scale: f32 = 0.35;
    const y_scale: f32 = 0.35;
    const x_size: i16 = @round(32 * x_scale);
    const y_size: i16 = @round(32 * y_scale);
    const x_rt: i16 = 640 - x_size;
    const y_bt: i16 = 480 - y_size;
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

    fn init_single(id: *u16, bottom: bool, right: bool) void {
        id.* = r.InitNewQuad(spr);
        rf.swrQuad_SetFlags(id.*, 1 << 15 | 1 << 16);
        if (right) rf.swrQuad_SetFlags(id.*, 1 << 2);
        if (!bottom) rf.swrQuad_SetFlags(id.*, 1 << 3);
        rf.swrQuad_SetColor(id.*, 0xFF, 0xFF, 0x9C, 0xFF);
        rf.swrQuad_SetPosition(id.*, if (right) x_rt else 0, if (bottom) y_bt else 0);
        rf.swrQuad_SetScale(id.*, x_scale, y_scale);
    }

    fn update(transition: f32, cr: u8, cg: u8, cb: u8) void {
        const active: bool = transition > 0;
        rf.swrQuad_SetActive(tl, @intFromBool(active));
        rf.swrQuad_SetActive(tr, @intFromBool(active));
        rf.swrQuad_SetActive(bl, @intFromBool(active));
        rf.swrQuad_SetActive(br, @intFromBool(active));
        if (active) {
            const opacity: u8 = @intFromFloat(nt.pow2(transition) * 255);
            rf.swrQuad_SetColor(tl, cr, cg, cb, opacity);
            rf.swrQuad_SetColor(tr, cr, cg, cb, opacity);
            rf.swrQuad_SetColor(bl, cr, cg, cb, opacity);
            rf.swrQuad_SetColor(br, cr, cg, cb, opacity);
        }
    }
};

// HOOK FUNCTIONS

pub fn InitRaceQuadsA(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    mode_vis.init();
}

// FIXME: corners not rendering in pre-race unless manually toggling practice mode
pub fn TextRenderB(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    const f = struct {
        const vis_time: f32 = 0.15;
        var start: ?u32 = null;
        var vis: f32 = 0;
        var prac: st.ActiveState = .Off;
    };

    f.prac.update(gs.practice_mode);

    if (gs.in_race == .JustOff) {
        f.start = null;
        f.vis = 0;
    }

    if (gs.in_race.on()) {
        mode_vis.update(0, 0, 0, 0);
        if (f.start == null or f.prac == .JustOn) f.start = gs.timestamp;
    } else return;

    f.vis += if (f.prac.on()) gs.dt_f else -gs.dt_f;
    f.vis = std.math.clamp(f.vis, 0, f.vis_time);

    if (f.vis == 0) return;

    if (f.start) |ts| {
        const vis_scalar: f32 = f.vis / f.vis_time;
        const t = @as(f32, @floatFromInt(gs.timestamp - ts)) / 1000;
        const color: u32 = fl.flash_color(@intFromEnum(rt.ColorRGB.Yellow), t, 3);
        mode_vis.update(vis_scalar, @truncate(color >> 16), @truncate(color >> 8), @truncate(color >> 0));
    }
}

//if (!s.prac.get("practice_tool_enable", bool)) return;
// FIXME: investigate past usage of practice tool ini setting; may need to adjust
// some things, primarily to do with lifecycle, because the past setting assumed
// it would be on permanently. also, do a pass on everything to integrate/migrate
// to global practice_mode.
pub fn EarlyEngineUpdateA(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    const toggle_input: bool = gf.InputGetKb(.P, .JustOn);

    // TODO: convert gs.practice_mode to ActiveState
    // TODO: queue toggling off for next reset from in race
    // TODO: disable toggling in race results screen
    if (toggle_input and
        (!gs.practice_mode or gs.race_state == .None or gs.race_state == .PreRace))
    {
        gs.practice_mode = !gs.practice_mode;
        const text: [:0]const u8 = if (gs.practice_mode) "Practice Mode Enabled" else "Practice Mode Disabled";
        _ = gf.ToastNew(text, rt.ColorRGB.Yellow.rgba(0));
    }
}
