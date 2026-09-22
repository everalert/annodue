//! primitive drawing api
//!
//! internal dependencies: AMemory, core "global state" (practice mode check)

const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;

const GlobalFn = @import("../appinfo.zig").GLOBAL_FUNCTION;
// FIXME: ?? should these ownership checks not be in some api? not necessarily
//  the public api but at least organized
const WorkingOwnerIsSystem = @import("AHook.zig").PluginState.WorkingOwnerIsSystem;

const core_draw = @import("../util/core/core_draw.zig");
const DrawSystem = core_draw.DrawSystem;

const ADAPI = @import("../util/api/api.zig");
const GDrawLayer = ADAPI.GDrawLayer;
const AMemoryGetPermanentT = ADAPI.helper.AMemoryGetPermanentT;

const MiB = @import("../util/base/base_memory.zig").MiB;

const r = @import("racer");
const rt = r.Text;
const TextDef = rt.TextDef;

const PATCH_BUFFER_SIZE = MiB(u32, 2);

const DrawState = struct {
    var bInitialized: bool = false;
    var System: DrawSystem = undefined;
};

//------------------------------------------------------------------------------
// annodue hooks

pub fn OnInit(gf: *GlobalFn) callconv(.C) void {
    var memory = AMemoryGetPermanentT(gf, [PATCH_BUFFER_SIZE]u8) orelse @panic("GDraw: API OutOfMemory");
    DrawState.System = DrawSystem.Init(memory) catch |e| panic("GDraw: {s}", .{@errorName(e)});
    DrawState.bInitialized = true;
}

pub fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

pub fn OnDeinit(_: *GlobalFn) callconv(.C) void {
    assert(DrawState.bInitialized);
    DrawState.System.Deinit();
}

pub fn Draw2DA(gf: *GlobalFn) callconv(.C) void {
    assert(DrawState.bInitialized);

    DrawState.System.LayerDraw(.Default, rt.DEFAULT_COLOR);
    if (gf.SPracticeMode()) DrawState.System.LayerDraw(.DefaultP, rt.DEFAULT_COLOR);

    // TODO: 'show overlay' user setting
    DrawState.System.LayerDraw(.Overlay, rt.DEFAULT_COLOR);
    if (gf.SPracticeMode()) DrawState.System.LayerDraw(.OverlayP, rt.DEFAULT_COLOR);

    DrawState.System.LayerDraw(.System, rt.DEFAULT_COLOR);
    if (gf.SPracticeMode()) DrawState.System.LayerDraw(.SystemP, rt.DEFAULT_COLOR);

    DrawState.System.LayerDraw(.Debug, rt.DEFAULT_COLOR);

    DrawState.System.Clear();
}

//------------------------------------------------------------------------------
// annodue api

/// queue text into Annodue render queue
/// - use racerlib->Text->MakeText to generate input
/// - string must be within 247 characters to fit into queue buffer
/// - set color 0 for layer-specific default
/// @return     true if text successfully added to queue
pub fn GDrawText(layer: GDrawLayer, text: ?*TextDef) callconv(.C) bool {
    assert(DrawState.bInitialized);
    if (text == null) return false;
    if ((layer == .System or layer == .SystemP) and !WorkingOwnerIsSystem()) return false;
    DrawState.System.TextInsert(layer, text.?) catch return false;
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
pub fn GDrawTextBox(layer: GDrawLayer, text: ?*TextDef, padding_x: i16, padding_y: i16, rect_color: u32) callconv(.C) bool {
    assert(DrawState.bInitialized);
    if (text == null) return false;
    if ((layer == .System or layer == .SystemP or layer == .Debug) and !WorkingOwnerIsSystem()) return false;

    DrawState.System.TextInsert(layer, text.?) catch return false;

    const d = rt.hTextGetDimensions(@ptrCast(&text.?.string));
    const a = rt.hTextGetAlignment(@ptrCast(&text.?.string));
    const offset_x = if (a == .Center) @divTrunc(-d.w, 2) else if (a == .Right) -d.w else 0;
    DrawState.System.RectInsert(
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
pub fn GDrawRect(layer: GDrawLayer, x: i16, y: i16, w: i16, h: i16, color: u32) callconv(.C) bool {
    assert(DrawState.bInitialized);
    if ((layer == .System or layer == .SystemP or layer == .Debug) and !WorkingOwnerIsSystem()) return false;
    DrawState.System.RectInsert(layer, x, y, w, h, color) catch return false;
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
) callconv(.C) bool {
    assert(DrawState.bInitialized);
    if ((layer == .System or layer == .SystemP or layer == .Debug) and !WorkingOwnerIsSystem()) return false;
    const bw = bdr_w;
    DrawState.System.RectInsert(layer, x + bw, y + bw, w - bw * 2, h - bw * 2, color) catch return false;
    DrawState.System.RectInsert(layer, x, y, w, bw, bdr_col) catch return false; // T
    DrawState.System.RectInsert(layer, x, y + h - bw, w, bw, bdr_col) catch return false; // B
    DrawState.System.RectInsert(layer, x, y + bw, bw, h - bw * 2, bdr_col) catch return false; // L
    DrawState.System.RectInsert(layer, x + w - bw, y + bw, bw, h - bw * 2, bdr_col) catch return false; // R
    return true;
}
