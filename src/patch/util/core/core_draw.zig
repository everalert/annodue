const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const panic = std.debug.panic;
const assert = std.debug.assert;

const r = @import("racer");
const rt = r.Text;
const rq = r.Quad;
const TextDef = rt.TextDef;
const ResetMaterial = r.Quad.ResetMaterial;

pub const DRAW_VERSION = 4;

// NOTE: system always last (on top)
pub const Layer = enum(u32) { Default, DefaultP, Overlay, OverlayP, System, SystemP, Debug };

// TODO: insertPanel, insertButton, etc. (after adding sprite drawing)
pub const DrawSystem = struct {
    const LayerCountBufferT = [@typeInfo(Layer).Enum.fields.len]u32;

    TextData: ArrayList(TextEntry),
    TextLayers: ArrayList(Layer),
    TextCounts: LayerCountBufferT,

    RectData: ArrayList(RectEntry),
    RectLayers: ArrayList(Layer),
    RectCounts: LayerCountBufferT,
    RectSprite: ?*rq.Sprite,

    ScratchBuffer: FixedBufferAllocator = undefined,
    ScratchAlloc: Allocator = undefined,

    const DEFAULT_RECT_COLOR: u32 = 0x00000080;

    pub fn Init(buf: []u8) !DrawSystem {
        var scratch_fba = FixedBufferAllocator.init(buf);
        const scratch_alloc = scratch_fba.allocator();

        return DrawSystem{
            .TextData = try ArrayList(TextEntry).initCapacity(scratch_alloc, 128),
            .TextLayers = try ArrayList(Layer).initCapacity(scratch_alloc, 128),
            .TextCounts = std.mem.zeroes(LayerCountBufferT),
            .RectData = try ArrayList(RectEntry).initCapacity(scratch_alloc, 32),
            .RectLayers = try ArrayList(Layer).initCapacity(scratch_alloc, 32),
            .RectCounts = std.mem.zeroes(LayerCountBufferT),
            .RectSprite = null,
            .ScratchBuffer = scratch_fba,
            .ScratchAlloc = scratch_alloc,
        };
    }

    pub fn Deinit(self: *DrawSystem) void {
        self.Clear();
        self.TextData.deinit();
        self.TextLayers.deinit();
        self.RectData.deinit();
        self.RectLayers.deinit();
        self.* = undefined;
    }

    pub fn Clear(self: *DrawSystem) void {
        self.TextData.clearRetainingCapacity();
        self.TextLayers.clearRetainingCapacity();
        self.TextCounts = std.mem.zeroes(LayerCountBufferT);
        self.RectData.clearRetainingCapacity();
        self.RectLayers.clearRetainingCapacity();
        self.RectCounts = std.mem.zeroes(LayerCountBufferT);
    }

    // TODO: return index, not success
    pub fn TextInsert(self: *DrawSystem, layer: Layer, text: *TextDef) !void {
        assert(std.mem.len(@as([*:0]u8, @ptrCast(&text.string))) <= 247);

        try self.TextLayers.append(layer);
        errdefer _ = self.TextLayers.pop();

        var data = try self.TextData.addOne();
        @memcpy(@as(*[256]u8, @ptrCast(data)), @as(*[256]u8, @ptrCast(text)));

        self.TextCounts[@intFromEnum(layer)] += 1;
    }

    // TODO: return index, not success
    pub fn RectInsert(self: *DrawSystem, layer: Layer, x: i16, y: i16, w: i16, h: i16, color: u32) !void {
        try self.RectLayers.append(layer);
        errdefer _ = self.RectLayers.pop();

        try self.RectData.append(.{ .x = x, .y = y, .w = w, .h = h, .color = color });

        self.RectCounts[@intFromEnum(layer)] += 1;
    }

    fn RectSetSpriteFromGameId(self: *DrawSystem, i: u32) bool {
        if (r.Quad.MapGet(i)) |sp| {
            self.RectSprite = sp;
            return true;
        }

        if (0 == r.Quad.MapLoad(i, null)) // FALSE
            return false;

        if (r.Quad.MapGet(i)) |sp| {
            self.RectSprite = sp;
            return true;
        }

        unreachable;
    }

    pub fn LayerDraw(self: *DrawSystem, layer: Layer, default_color: u32) void {
        //if (quad_refs[@intFromEnum(layer)] > 0) {
        //    ResetMaterial();
        //    for (quad_data) |*q| {
        //        rq.DrawQuad(@ptrFromInt(0xE9BA80), -1, 0.5, 0.5);
        //    }
        //}

        if (self.RectSprite != null and
            self.RectCounts[@intFromEnum(layer)] > 0 and
            self.RectSetSpriteFromGameId(26)) // white square texture
        {
            ResetMaterial();
            for (self.RectLayers.items, self.RectData.items) |l, *rect| {
                if (l != layer) continue;
                const color: u32 = if (rect.color & 0xFF > 0) rect.color else DEFAULT_RECT_COLOR;
                rq.DrawSprite(
                    self.RectSprite,
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

        if (self.TextCounts[@intFromEnum(layer)] > 0) {
            ResetMaterial();
            for (self.TextLayers.items, self.TextData.items) |l, *t| {
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

// TODO: assert/test sizeof = 256 bytes
// NOTE: strings above around 256 characters seems pointless even with excessive
//  formatting characters, but may be worth reconsidering down the line for things
//  like higher res viewport
const TextEntry = extern struct {
    x: i16,
    y: i16,
    color: u32, // alpha 0 = default color (i.e. 0 = no color)
    string: [247:0]u8, // fit to 64-byte cache line boundary
};

// TODO: assert/test sizeof = 12 bytes
// TODO: merge with generalized sprite drawing down the line
const RectEntry = extern struct {
    x: i16,
    y: i16,
    w: i16,
    h: i16,
    color: u32, // 0 = default color (i.e. 0 = no color)
};
