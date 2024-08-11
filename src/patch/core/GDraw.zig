const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const GlobalSt = @import("../appinfo.zig").GLOBAL_STATE;
const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;
const workingOwnerIsSystem = @import("Hook.zig").PluginState.workingOwnerIsSystem;

const coreAllocator = @import("Allocator.zig").allocator;

const PPanic = @import("../util/debug.zig").PPanic;

const r = @import("racer");
const rt = r.Text;
const rq = r.Quad;
const TextDef = rt.TextDef;
const ResetMaterial = r.Quad.ResetMaterial;

pub const GDRAW_VERSION: usize = 4;

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
const GDraw = struct {
    var text_data: ArrayList(GDrawTextDef) = undefined;
    var text_layers: ArrayList(GDrawLayer) = undefined;
    var text_refs = std.mem.zeroes([@typeInfo(GDrawLayer).Enum.fields.len]u32);
    var rect_data: ArrayList(GDrawRectDef) = undefined;
    var rect_layers: ArrayList(GDrawLayer) = undefined;
    var rect_refs = std.mem.zeroes([@typeInfo(GDrawLayer).Enum.fields.len]u32);
    var rect_sprite: ?*rq.Sprite = null;

    pub fn init(allocator: Allocator) !void {
        text_data = try ArrayList(GDrawTextDef).initCapacity(allocator, 128);
        text_layers = try ArrayList(GDrawLayer).initCapacity(allocator, 128);
        rect_data = try ArrayList(GDrawRectDef).initCapacity(allocator, 32);
        rect_layers = try ArrayList(GDrawLayer).initCapacity(allocator, 32);
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
                rt.RenderSetColor(
                    @as(u8, @truncate(color >> 24)),
                    @as(u8, @truncate(color >> 16)),
                    @as(u8, @truncate(color >> 8)),
                    @as(u8, @truncate(color >> 0)),
                );
                rt.RenderSetPosition(t.x, t.y);
                rt.RenderString(&t.string);
            }
        }
    }
};

// GLOBAL EXPORTS

/// queue text into Annodue render queue
/// - use racerlib->Text->MakeText to generate input
/// - string must be within 247 characters to fit into queue buffer
/// - set color 0 for layer-specific default
/// @return     true if text successfully added to queue
pub fn GDrawText(layer: GDrawLayer, text: ?*TextDef) bool {
    if (text == null) return false;
    if ((layer == .System or layer == .SystemP) and !workingOwnerIsSystem()) return false;
    GDraw.insertText(layer, text.?) catch return false;
    return true;
}

// FIXME: crashes due to GetStringWidth/GetStringHeight calls in TextGetDimensions
// TODO: add to global functions
/// queue text with background rect into Annodue render queue
/// - use racerlib->Text->MakeText to generate text input
/// - string must be within 247 characters to fit into queue buffer
/// - set color 0 in text for layer-specific default
/// - set rect_color 0 for default
/// @return     true if text successfully added to queue
pub fn GDrawTextBox(layer: GDrawLayer, text: ?*TextDef, padding_x: i16, padding_y: i16, rect_color: u32) bool {
    if (text == null) return false;
    if ((layer == .System or layer == .SystemP or layer == .Debug) and !workingOwnerIsSystem()) return false;

    GDraw.insertText(layer, text.?) catch return false;

    const d = rt.TextGetDimensions(@ptrCast(&text.?.string));
    const a = rt.TextGetAlignment(@ptrCast(&text.?.string));
    const offset_x = if (a == .Center) @divTrunc(-d.w, 2) else if (a == .Right) -d.w else 0;
    GDraw.insertRect(
        layer,
        text.?.x - padding_x - offset_x,
        text.?.y - padding_y,
        d.w + padding_x * 2,
        d.h + padding_y * 2,
        rect_color,
    ) catch return false;
    return true;
}

/// queue rect into Annodue render queue
/// will be drawn under text of the same layer
/// - set color 0 for default
/// @return     true if rect successfully added to queue
pub fn GDrawRect(layer: GDrawLayer, x: i16, y: i16, w: i16, h: i16, color: u32) bool {
    if ((layer == .System or layer == .SystemP or layer == .Debug) and !workingOwnerIsSystem()) return false;
    GDraw.insertRect(layer, x, y, w, h, color) catch return false;
    return true;
}

/// queue rect with border into Annodue render queue
/// will be drawn under text of the same layer
/// - set color 0 for default
/// @return     true if rect successfully added to queue
pub fn GDrawRectBdr(
    layer: GDrawLayer,
    x: i16,
    y: i16,
    w: i16,
    h: i16,
    color: u32,
    bdr_w: i16,
    bdr_col: u32,
) bool {
    if ((layer == .System or layer == .SystemP or layer == .Debug) and !workingOwnerIsSystem()) return false;
    const bw = bdr_w;
    GDraw.insertRect(layer, x + bw, y + bw, w - bw * 2, h - bw * 2, color) catch return false;
    GDraw.insertRect(layer, x, y, w, bw, bdr_col) catch return false; // T
    GDraw.insertRect(layer, x, y + h - bw, w, bw, bdr_col) catch return false; // B
    GDraw.insertRect(layer, x, y + bw, bw, h - bw * 2, bdr_col) catch return false; // L
    GDraw.insertRect(layer, x + w - bw, y + bw, bw, h - bw * 2, bdr_col) catch return false; // R
    return true;
}

// HOOKS

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    GDraw.init(coreAllocator()) catch @panic("GDraw init failed");
}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    GDraw.deinit();
}

pub fn Draw2DA(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    GDraw.rect_sprite = r.Quad.MapGet(26);
    if (GDraw.rect_sprite == null) {
        _ = r.Quad.MapLoad(26, null);
        GDraw.rect_sprite = r.Quad.MapGet(26);
    }

    GDraw.drawLayer(.Default, rt.DEFAULT_COLOR);
    if (gs.practice_mode) GDraw.drawLayer(.DefaultP, rt.DEFAULT_COLOR);

    // TODO: 'show overlay' user setting
    GDraw.drawLayer(.Overlay, rt.DEFAULT_COLOR);
    if (gs.practice_mode) GDraw.drawLayer(.OverlayP, rt.DEFAULT_COLOR);

    GDraw.drawLayer(.System, rt.DEFAULT_COLOR);
    if (gs.practice_mode) GDraw.drawLayer(.SystemP, rt.DEFAULT_COLOR);

    GDraw.drawLayer(.Debug, rt.DEFAULT_COLOR);

    GDraw.clear();
}
