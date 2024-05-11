const std = @import("std");
const mem = @import("memory.zig");

const racer = @import("racer");
const rd = racer.RaceData;
const e = racer.Entity;
const c = racer.constants;
const f = racer.functions;
const t = racer.text;

// SCREEN SPACE QUAD DRAWING

pub fn InitNewQuad(spr: u32) u16 {
    const i: u16 = mem.read(c.ADDR_QUAD_INITIALIZED_INDEX, u16);
    f.swrQuad_InitQuad(i, spr);
    _ = mem.write(c.ADDR_QUAD_INITIALIZED_INDEX, u16, i + 1);
    return i;
}
