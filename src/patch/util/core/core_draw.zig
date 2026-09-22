const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const r = @import("racer");
const rt = r.Text;
const rq = r.Quad;
const TextDef = rt.TextDef;
const ResetMaterial = r.Quad.ResetMaterial;

pub const GDRAW_VERSION = 4;

// NOTE: anything above around 256 characters seems pointless even with excessive formatting
// characters, but may be worth reconsidering down the line if e.g. higher res viewport

// NOTE: system always last (on top)
pub const GDrawLayer = enum(u32) { Default, DefaultP, Overlay, OverlayP, System, SystemP, Debug };

// TODO: assert/test sizeof = 256 bytes
const GDrawTextDef = extern struct {
    x: i16,
    y: i16,
    color: u32, // alpha 0 = default color (i.e. 0 = no color)
    string: [247:0]u8, // fit to 64-byte cache line boundary
};

// TODO: assert/test sizeof = 12 bytes
// TODO: merge with generalized sprite drawing down the line
const GDrawRectDef = extern struct {
    x: i16,
    y: i16,
    w: i16,
    h: i16,
    color: u32, // 0 = default color (i.e. 0 = no color)
};

// TODO: insertPanel, insertButton, etc. (after adding sprite drawing)
pub const GDraw = struct {
    var text_data: ArrayList(GDrawTextDef) = undefined;
    var text_layers: ArrayList(GDrawLayer) = undefined;
    var text_refs = std.mem.zeroes([@typeInfo(GDrawLayer).Enum.fields.len]u32);
    var rect_data: ArrayList(GDrawRectDef) = undefined;
    var rect_layers: ArrayList(GDrawLayer) = undefined;
    var rect_refs = std.mem.zeroes([@typeInfo(GDrawLayer).Enum.fields.len]u32);
    var rect_sprite: ?*rq.Sprite = null;

    var scratch_fba: FixedBufferAllocator = undefined;
    var scratch_alloc: Allocator = undefined;

    pub fn init(buf: []u8) !void {
        scratch_fba = FixedBufferAllocator.init(buf);
        scratch_alloc = scratch_fba.allocator();
        text_data = try ArrayList(GDrawTextDef).initCapacity(scratch_alloc, 128);
        text_layers = try ArrayList(GDrawLayer).initCapacity(scratch_alloc, 128);
        rect_data = try ArrayList(GDrawRectDef).initCapacity(scratch_alloc, 32);
        rect_layers = try ArrayList(GDrawLayer).initCapacity(scratch_alloc, 32);
    }

    pub fn deinit() void {
        clear();
        text_data.deinit();
        text_layers.deinit();
        rect_data.deinit();
        rect_layers.deinit();
    }

    pub fn clear() void {
        text_data.clearRetainingCapacity();
        text_layers.clearRetainingCapacity();
        text_refs = std.mem.zeroes(@TypeOf(text_refs));
        rect_data.clearRetainingCapacity();
        rect_layers.clearRetainingCapacity();
        rect_refs = std.mem.zeroes(@TypeOf(text_refs));
    }

    // TODO: return index, not success
    pub fn insertText(layer: GDrawLayer, text: *TextDef) !void {
        std.debug.assert(std.mem.len(@as([*:0]u8, @ptrCast(&text.string))) <= 247);

        try text_layers.append(layer);
        errdefer _ = text_layers.pop();

        var data = try text_data.addOne();
        @memcpy(@as(*[256]u8, @ptrCast(data)), @as(*[256]u8, @ptrCast(text)));

        text_refs[@intFromEnum(layer)] += 1;
    }

    // TODO: return index, not success
    pub fn insertRect(layer: GDrawLayer, x: i16, y: i16, w: i16, h: i16, color: u32) !void {
        try rect_layers.append(layer);
        errdefer _ = rect_layers.pop();

        try rect_data.append(.{ .x = x, .y = y, .w = w, .h = h, .color = color });

        rect_refs[@intFromEnum(layer)] += 1;
    }

    pub fn setRectSpriteFromGameId(i: u32) bool {
        if (r.Quad.MapGet(i)) |sp| {
            rect_sprite = sp;
            return true;
        }

        if (0 == r.Quad.MapLoad(i, null)) // FALSE
            return false;

        if (r.Quad.MapGet(i)) |sp| {
            rect_sprite = sp;
            return true;
        }

        unreachable;
    }

    const DEFAULT_RECT_COLOR: u32 = 0x00000080;

    pub fn drawLayer(layer: GDrawLayer, default_color: u32) void {
        //if (quad_refs[@intFromEnum(layer)] > 0) {
        //    ResetMaterial();
        //    for (quad_data) |*q| {
        //        rq.DrawQuad(@ptrFromInt(0xE9BA80), -1, 0.5, 0.5);
        //    }
        //}

        if (rect_sprite != null and rect_refs[@intFromEnum(layer)] > 0) {
            ResetMaterial();
            for (rect_layers.items, rect_data.items) |l, *rect| {
                if (l != layer) continue;
                const color: u32 = if (rect.color & 0xFF > 0) rect.color else DEFAULT_RECT_COLOR;
                rq.DrawSprite(
                    GDraw.rect_sprite,
                    rect.x,
                    rect.y,
                    @as(f32, @floatFromInt(rect.w)) / 8,
                    @as(f32, @floatFromInt(rect.h)) / 8,
                    0,
                    0,
                    0,
                    0,
                    @as(u8, @truncate(color >> 24)),
                    @as(u8, @truncate(color >> 16)),
                    @as(u8, @truncate(color >> 8)),
                    @as(u8, @truncate(color >> 0)),
                );
            }
        }

        if (text_refs[@intFromEnum(layer)] > 0) {
            ResetMaterial();
            for (text_layers.items, text_data.items) |l, *t| {
                if (l != layer) continue;
                const color: u32 = if (t.color & 0xFF > 0) t.color else default_color;
                rt.fnRenderSetColor(
                    @as(u8, @truncate(color >> 24)),
                    @as(u8, @truncate(color >> 16)),
                    @as(u8, @truncate(color >> 8)),
                    @as(u8, @truncate(color >> 0)),
                );
                rt.fnRenderSetPosition(t.x, t.y);
                rt.fnRenderString(&t.string);
            }
        }
    }
};
