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

pub const GDRAW_VERSION: usize = 2;

// NOTE: anything above around 256 characters seems pointless even with excessive formatting
// characters, but may be worth reconsidering down the line if e.g. higher res viewport

// TODO: assert/test sizeof = 256 bytes
const GDrawTextDef = extern struct {
    x: i16,
    y: i16,
    color: u32, // alpha 0 = default color (i.e. 0 = no color)
    string: [247:0]u8, // fit to 64-byte cache line boundary
};

// NOTE: system always last (on top)
pub const GDrawLayer = enum(u32) { Default, DefaultP, Overlay, OverlayP, System, SystemP };

// TODO: insertPanel, insertButton, etc. (after adding sprite drawing)
const GDraw = struct {
    var text_data: ArrayList(GDrawTextDef) = undefined;
    var text_layers: ArrayList(GDrawLayer) = undefined;
    var text_refs = std.mem.zeroes([@typeInfo(GDrawLayer).Enum.fields.len]u32);

    pub fn init(allocator: Allocator) !void {
        text_data = try ArrayList(GDrawTextDef).initCapacity(allocator, 128);
        text_layers = try ArrayList(GDrawLayer).initCapacity(allocator, 128);
    }

    pub fn deinit() void {
        clear();
        text_data.deinit();
        text_layers.deinit();
    }

    pub fn clear() void {
        text_data.clearRetainingCapacity();
        text_layers.clearRetainingCapacity();
        text_refs = std.mem.zeroes(@TypeOf(text_refs));
    }

    pub fn insertText(layer: GDrawLayer, text: *TextDef) !void {
        std.debug.assert(std.mem.len(@as([*:0]u8, @ptrCast(&text.string))) <= 247);

        try text_layers.append(layer);
        errdefer _ = text_layers.pop();

        var data = try text_data.addOne();
        @memcpy(@as(*[256]u8, @ptrCast(data)), @as(*[256]u8, @ptrCast(text)));

        text_refs[@intFromEnum(layer)] += 1;
    }

    pub fn drawLayer(layer: GDrawLayer, default_color: u32) void {
        //if (quad_refs[@intFromEnum(layer)] > 0) {
        //    ResetMaterial();
        //    for (quad_data) |*q| {
        //        rq.DrawQuad(@ptrFromInt(0xE9BA80), -1, 0.5, 0.5);
        //    }
        //}

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

// HOOKS

pub fn OnInit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    GDraw.init(coreAllocator()) catch @panic("GDraw init failed");
}

pub fn OnInitLate(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    GDraw.deinit();
}

pub fn Draw2DA(gs: *GlobalSt, _: *GlobalFn) callconv(.C) void {
    GDraw.drawLayer(.Default, rt.DEFAULT_COLOR);
    if (gs.practice_mode) GDraw.drawLayer(.DefaultP, rt.DEFAULT_COLOR);

    // TODO: 'show overlay' user setting
    GDraw.drawLayer(.Overlay, rt.DEFAULT_COLOR);
    if (gs.practice_mode) GDraw.drawLayer(.OverlayP, rt.DEFAULT_COLOR);

    GDraw.drawLayer(.System, rt.DEFAULT_COLOR);
    if (gs.practice_mode) GDraw.drawLayer(.SystemP, rt.DEFAULT_COLOR);

    GDraw.clear();
}
