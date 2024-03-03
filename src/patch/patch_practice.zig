pub const Self = @This();

const std = @import("std");

const s = @import("settings.zig").state;
const GlobalState = @import("global.zig").GlobalState;
const GlobalFn = @import("global.zig").GlobalFn;

const mem = @import("util/memory.zig");
const r = @import("util/racer.zig");
const rc = r.constants;
const rf = r.functions;

// PRACTICE MODE VISUALIZATION

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

// HOOK FUNCTIONS

pub fn InitRaceQuadsA(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    _ = gs;
    mode_vis.init();
}

pub fn TextRenderB(gs: *GlobalState, gv: *GlobalFn, initialized: bool) callconv(.C) void {
    _ = gv;
    _ = initialized;
    if (!s.prac.get("practice_tool_enable", bool) or !s.prac.get("overlay_enable", bool)) return;

    if (gs.in_race.on()) {
        var buf: [127:0]u8 = undefined;
        _ = buf;

        const race_times: [6]f32 = mem.deref_read(&.{ rc.ADDR_RACE_DATA, 0x60 }, [6]f32);
        const total_time: f32 = race_times[5];

        // FIXME: move flashing logic out of here
        // FIXME: make the flashing start when you activate practice mode
        var f_r: u8 = 0xFF;
        var f_g: u8 = 0xFF;
        var f_b: u8 = 0x9C;
        var f_on: bool = false;
        if (gs.practice_mode) {
            const r_range: u8 = 0xFF / 2;
            const g_range: u8 = 0xFF / 2;
            const b_range: u8 = 0x9C / 2;
            if (total_time <= 0) {
                const timer: f32 = r.ReadEntityValue(.Jdge, 0, 0x0C, f32);
                const flash_cycle: f32 = std.math.clamp((std.math.cos(timer * std.math.pi * 12) * 0.5 + 0.5) * std.math.pow(f32, timer / 3, 3), 0, 3);
                f_r -= @intFromFloat(r_range * flash_cycle);
                f_g -= @intFromFloat(g_range * flash_cycle);
                f_b -= @intFromFloat(b_range * flash_cycle);
            }
            // TODO: move text to eventual toast system
            //rf.swrText_CreateEntry1(640 - 16, 480 - 16, f_rg, f_rg, f_b, 190, "~F0~s~rPractice Mode");
            f_on = true;
        }
        mode_vis.update(f_on, f_r, f_g, f_b);
    }
}
