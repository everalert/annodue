const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

const GlobalFn = @import("appinfo.zig").GLOBAL_FUNCTION;
const COMPATIBILITY_VERSION = @import("appinfo.zig").COMPATIBILITY_VERSION;
const VERSION_STR = @import("appinfo.zig").VERSION_STR;

const debug = @import("core/Debug.zig");

const crot = @import("util/color.zig");
const mem = @import("util/memory.zig");
const x86 = @import("util/x86.zig");
const PPanic = @import("util/debug.zig").PPanic;
const TGA = @import("util/tga.zig");

const SettingHandle = @import("core/ASettings.zig").Handle;
const SettingValue = @import("core/ASettings.zig").ASettingSent.Value;
const Setting = @import("core/ASettings.zig").ASettingSent;

const ra = @import("racer").Asset;
const rt = @import("racer").Text;
const rf = @import("racer").Font;
const r3 = @import("racer").@"3D";

// TODO: passthrough to annodue's panic via global function vtable; same for logging
pub const panic = debug.annodue_panic;

// FIXME: using ConsoleOut from here allows general logging to be spat out in the
//  ConsoleOut window (see: gif.zig), meaning you don't actually have to call
//  ConsoleOut to write to console once the window is actually up. maybe the
//  ConsoleOut API should be adjusted to reflect this? maybe just have an
//  enable/disable console API function in annodue, and let the user do whatever
//  they want to actually forward console writes? might be more convenient to
//  manage scoped logging this way
// FIXME: remove, for testing
const dbg = @import("util/debug.zig");
const rd = @import("racer").Debug;

// FIXME: review all fixme/todo in this file and consolidate in normal annodue
// notes/todo file, so that stuff doesn't get lost or forgotten

// TODO: ROADMAP
// - texture loader/manager in core, that caches GPU references to loaded textures
//   instead of freeing them when no longer used; i.e. avoid creating GPU resources
//   unnecessarily, as a way to avoid the "memory leak crash". one other avenue
//   to explore here is having an actual texture atlas, to minimize the absolute
//   number of GPU resources needed. See the Display_VSurfaceLock, etc. family
//   of functions for a way to do this, example usage and logic flow in VBufferLock,
//   MaterialLoadEntry, the screenshot function, etc.. Will need to manage own
//   VBuffers and therefore reimpl the functionality around these (again, see
//   MaterialLoadEntry)
// - font loader/manager as a plugin. pixel data stored in the plugin, and copied
//   to the font texture directly whenever the user swaps font choice (i.e. there
//   is only one texture used in the font system, use VSurfaceLock etc. for this).
//   font api should take a 'nice' image of glyphs rather than ones organized like
//   the game fonts, and therefore needs to also accommodate custom font definitions
//   that have different glyph coordinates accordingly. Plugin developers should
//   also have the option to provide their own font definitions, so the system
//   must be able to translate the font definition coordinates to the font atlas
//   texture coordinates at runtime. regular users should be able to just place
//   an image file matching the standard font def in 'annodue/fonts' or somewhere
//   and have it appear as an option in the game. the standard font def should also
//   have the glyph coordinates cleaned up so users can actually make fonts that
//   use the currently busted glyphs (like '!')
//      - mod brainstorming:
//          - user option to not use the added margins on the planned "standard"
//            fonts; changes the look of the glyphs a little because the cutoff
//            on the original font makes some parts look more solid/blocky
//          - two standard fonts (ones where you can just drop an image into a
//            folder): a "minimal" one that only has the stock font glyphs, and
//            a "normal" one as originally planned that expands on available
//            glyphs but keeps the stock ones faithfully sized etc
//          - custom extended glyph defs (LUT) by overwriting game memory (the
//            stuff at 4BFA10, 4BFA58)
//          - feature to dump or otherwise display the font defs, glyph defs,
//            extended glyph LUT, etc. as text/csv
// - remake old HD font with better proportions that actually match the original
//   font
// - future: some kind of text rendering system that lets developers draw with
//   fonts other than the ones the game is using? also could be useful as a
//   way of dodging the triangle count limitations imposed by the game's normal
//   rendering system (all text, geo, etc. is dumped into the same queue that
//   draw calls are made from, which has a limit), and could also open the door
//   for an imgui down the line

// NOTE: scratchpad notes
//
// mod
// - make 'fixed' base font patch option with the minor adjustments that work with
//   the original font defs/textures, using some kind of 'adjustment table'
// - then use that as a base and apply changes from another such adjustment table
//   for the custom font def
// - i.e. 'progressively enhance' from the base fonts, to simplify figuring out all
//   the new numbers
// - general rule = 'basic custom font' should not introduce any glyphs that do not
//   already have pixels drawn on the original font, and should not make any changes
//   that affect the spacing of the output; but adjustments to coords and splitting
//   overlapping defs into independent mappings OK; this is so that it can serve as
//   a 'ground truth' baseline representing a user who has no custom fonts enabled
// - font dll should have the timings adjusted so that the original fonts are fully
//   loaded before executing any mods; that way the 'copied' versions can use the
//   prepared resources (i.e. default to late-loading, and only execute on any
//   features before font loading when that feature really needs it)
//
// notes
// - can't totally fix accent alignment, because differences in base character width
//   naturally misalign them; can only fix this case in code
// - can't make inverted exclamation mark in the way '?' is done without changing
//   code; but could just make another glyph
// - loading textures into gpu seems to be the cause of the "memory leak" crash?
//   so the plan is to just reuse a single texture and rewrite the pixels whenever
//   a font is changed/loaded. not sure if this is a dgvoodoo problem or just a
//   windows regression. still need to completely rule out game allocations because
//   there is one place during material generation that temp allocates

// TODO: all settings hot-reloadable
// TODO: embed fonts and point to ours, rather than patching the whole thing (for faster loadtimes)
// TODO: dump fonts as a button on a menu, not a weirdge on-launch only thing
// TODO: option to show double-size fonts on font test visualization
// TODO: ingame menu (not necessarily adding the menu itself during this pass, but
// some of these features should still be implemented now as settings file stuff)
// - buttons for the dumping ("developer") features
// - font selector
// - button to clear cached fonts (including or excluding ones without a paired gif)
// - button to reload fonts
// - button to add/remove glyph margins
// - exotic stuff (e.g. font designer/importer)
// - show test strings for previewing fonts
// - opt to show font textures directly?
// FIXME: change user of custom fonts to something like "annodue/custom/fonts";
// i.e. part of a unified location for custom content
// FIXME: update changelog and manual to reflect new font functionality and stuff
// inherited from cosmetic/developer plugins, as well as updating old parts of
// current changelog that talk about font-related features on other plugins in
// this release round

// NOTE: consider halving old hd font, as this would enable the max texture size
// of custom fonts to be 4x less. in this case, glyphs will still be oversized for
// normal text, but undersized for "large" text (~75% @ 1440p, ~85-90% @ 1080p).
// possibly acceptable (unscaled non-large normal body text @ 960p has similar
// ratio and is subjectively good-looking), but ~6x base size would be needed for
// no/minimal scaling in all cases; 8x is actually justified for pow2.
// NOTE: technically, fonts probably don't need to be in the pixel format the
// game uses; might be possible to just accept any format, including colored, and
// just translate to ARGB4444/ARGB1555 in our loader. unsure if this is a good
// idea, for now just mimicking the game format closely.
// NOTE: sample old code lines showing the old .data files were GA88-format pixels
//var path = std.fmt.bufPrintZ(&str_buf, "annodue/textures/{s}_{d}_test.data", .{ filename, page }) catch
//buffer_slice[j / 2] |= ra.hInsert4BPP(ra.hGA88toG4(px), j);

// FEATURES
// - custom font loading system, shipping with existing high definition font
// - adjust font glyph defs to align more nicely and support more characters
// - bugfix font glyph uv mapping during clipping
// - ability to dump base game font data to file (glyph texture and UV mask images, font definition data)
// - ability to display font testing text
// - SETTINGS:
//   enable                 bool    enable custom font system and associated font fixes
//   font                   string  name of gif file (in /annodue/custom/font) used
//                                  for currently shown font; use "STOCK" to display
//                                  base game font with fixes
//   can_show_test          bool    enable displaying font test text
//   can_dump_data          bool    enable dumping source ingame font data to /annodue/developer
//   can_dump_glyphs        bool    enable dumping glyph binary data of currently loaded font

const PLUGIN_NAME: [*:0]const u8 = "Font";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

//------------------------------------------------------------------------------
// plugin housekeeping

export fn PluginName() callconv(.C) [*:0]const u8 {
    return PLUGIN_NAME;
}

export fn PluginVersion() callconv(.C) [*:0]const u8 {
    return PLUGIN_VERSION;
}

export fn PluginCompatibilityVersion() callconv(.C) u32 {
    return COMPATIBILITY_VERSION;
}

// NOTE: other fonts init in TextRenderB
export fn OnInit(gf: *GlobalFn) callconv(.C) void {
    // TODO: remove; this is only here because not referencing the variable
    //  causes it to sometimes be initialized to a garbage value (even though
    //  it's explitly set in the def), which causes an oob error below. unsure
    //  of the cause, may not be an issue after upgrading from zig 0.11, and
    //  might not come up after the globals get consolidated into structures.
    fonts_custom_active = false;

    FontState.settingsInit(gf);
}

export fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalFn) callconv(.C) void {
    FontsUnload();
}

//------------------------------------------------------------------------------
// plugin hooks

// TODO: "better" control flow that actually shows the implication that fonts
//  will only be loaded when the 'enable' setting is on?
export fn TextRenderB(gf: *GlobalFn) callconv(.C) void {
    // NOTE: original function at fn_42D720
    // making sure original fonts are fully loaded before this runs
    if (!fonts_loaded and FontState.s_enable) {
        FontsLoad();
    }

    // toggle custom fonts
    if (fonts_loaded and gf.InputGetKbRaw(.K) == .JustOn) {
        fonts_active = !fonts_active;
        const font = if (!fonts_active) null else if (!fonts_custom_active) &font_stock_custom else &font_custom;
        UpdateGameFont(font);
    }

    // TODO: remove this once actually loading custom font based on setting; maybe
    //  the hotkey can be brought back later when the menu stuff is implemented tho,
    //  since you will be able to scroll them in the menu and that could be easily
    //  translated back to the hotkey (or a cycle font forward/back pair)
    // cycle displayed custom font
    if (fonts_loaded and fonts_active and gf.InputGetKbRaw(.L) == .JustOn) {
        fonts_custom_active = !fonts_custom_active;
        const font = if (!fonts_active) null else if (!fonts_custom_active) &font_stock_custom else &font_custom;
        UpdateGameFont(font);
    }

    // TODO: use annodue text instead so that it can scale with unlimited text
    //  and be cleaner?
    // testing display showing all(?) font glyphs
    if (FontState.s_can_show_test and gf.InputGetKbRaw(.O).on()) {
        var buf: [255:0]u8 = undefined;
        var x: i16 = 12;
        var y: i16 = 128;

        rt.swrText_CreateEntry1(x, y, 0xFF, 0xFF, 0xFF, 0xFF, "~F0~3~sFONT TEST");
        y += 10;
        const label: ?[*:0]const u8 = std.fmt.bufPrintZ(&buf, "~F4~3~s{s}", .{
            if (!fonts_active) "base font" else if (!fonts_custom_active) &font_stock_custom.Name else &font_custom.Name,
        }) catch null;
        rt.swrText_CreateEntry1(x, y, 0xFF, 0xFF, 0xFF, 0xFF, label);
        y += 24;

        for (0..5) |i| {
            const y_step: i16 = if (i < 4) 12 else 32;
            for (0..4) |j| {
                rt.swrText_CreateEntry1(x, y, 0xFF, 0xFF, 0xFF, 0xFF, &font_test_strings[i + 2][j]);
                y += y_step;
            }
        }
    }

    // font data dump
    if (FontState.s_can_dump_data and gf.InputGetKbRaw(.I) == .JustOn) {
        FontState.FontDump();
        _ = gf.ToastNew("Font data dumped to /annodue/developer", 0xFFFFFFFF);
    }

    // TODO: setting to use manually generated adjustments instead of stored ones
    // FIXME: will need a different place to store the generated fixed glyphs, once
    //  fonts are loaded dynamically. should also probably generate the adjustments
    //  ahead of time even if the user hasn't loaded any fonts yet, to remove the
    //  dependency dumping currently has of the custom font actually being made, as
    //  well as potentially simplifying the custom font loading process.
    // font glyph binary data dump
    if (FontState.s_can_dump_glyphs and fonts_active and gf.InputGetKbRaw(.E) == .JustOn) blk: {
        font_stock_fixed.GlyphBinDump("annodue/developer/fontcustom_glyphs_fixed.bin") catch {
            _ = gf.ToastNew("Error dumping font fixed glyphs", rt.ColorRGB.Red.rgba(0xFF));
            break :blk;
        };
        _ = gf.ToastNew("Font fixed glyphs dumped to /annodue/developer", rt.ColorRGB.White.rgba(0xFF));

        font_stock_custom.GlyphBinDump("annodue/developer/fontcustom_glyphs_custom.bin") catch {
            _ = gf.ToastNew("Error dumping font custom glyphs", rt.ColorRGB.Red.rgba(0xFF));
            break :blk;
        };
        _ = gf.ToastNew("Font custom glyphs dumped to /annodue/developer", rt.ColorRGB.White.rgba(0xFF));
    }
}

//------------------------------------------------------------------------------
// plugin state

const FontState = struct {
    var h_s_section: ?SettingHandle = null;
    var h_s_enable: ?SettingHandle = null;
    var h_s_font: ?SettingHandle = null;
    var h_s_can_show_test: ?SettingHandle = null;
    var h_s_can_dump_data: ?SettingHandle = null;
    var h_s_can_dump_glyphs: ?SettingHandle = null;
    var s_enable: bool = false;
    var s_font: [63:0]u8 = "STOCK";
    var s_can_show_test: bool = false;
    var s_can_dump_data: bool = false;
    var s_can_dump_glyphs: bool = false;

    var dump_fonts_done: bool = false;

    pub fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "font", null);
        h_s_section = section;

        h_s_enable =
            gf.ASettingOccupy(section, "enable", .B, .{ .b = true }, &s_enable, null);
        h_s_font =
            gf.ASettingOccupy(section, "font", .Str, .{ .str = "STOCK" }, &s_enable, null);

        // TODO: more of these debug toggles?
        h_s_can_show_test =
            gf.ASettingOccupy(section, "can_show_test", .B, .{ .b = false }, &s_can_show_test, null);
        h_s_can_dump_data =
            gf.ASettingOccupy(section, "can_dump_data", .B, .{ .b = false }, &s_can_dump_data, null);
        h_s_can_dump_glyphs =
            gf.ASettingOccupy(section, "can_dump_glyphs", .B, .{ .b = false }, &s_can_dump_glyphs, null);
    }

    // WARN: should be used after game init is done, e.g. in response to a button
    //  press. may crash the game if called too early during game init.
    pub fn FontDump() void {
        dump_fonts_done = true;
        var font: [5][0x2000]u8 = undefined;

        ExtractRawFontPagesToGrey8(&font);
        DumpGrey8toTGA(&font[0], 64, 128, "annodue/developer/fontraw0.tga");
        DumpGrey8toTGA(&font[1], 64, 128, "annodue/developer/fontraw1.tga");
        DumpGrey8toTGA(&font[2], 64, 128, "annodue/developer/fontraw2.tga");
        DumpGrey8toTGA(&font[3], 64, 128, "annodue/developer/fontraw3.tga");
        DumpGrey8toTGA(&font[4], 64, 128, "annodue/developer/fontraw4.tga");

        // TODO: resolve or filter out garbage glyph defs polluting templates
        // TODO: draw each glyph as a separate image, to account for overlaps?
        font = std.mem.zeroes([5][0x2000]u8);
        DrawGlyphRegions(&[_][]rf.GLYPH{ rf.aFontGlyphs0, rf.aFontGlyphs0Ext }, &[_][]u8{ &font[0], &font[1], &font[2] }, 64, 128);
        DrawGlyphRegions(&[_][]rf.GLYPH{rf.aFontGlyphs1}, &[_][]u8{&font[2]}, 64, 128);
        DrawGlyphRegions(&[_][]rf.GLYPH{rf.aFontGlyphs2}, &[_][]u8{&font[2]}, 64, 128);
        DrawGlyphRegions(&[_][]rf.GLYPH{ rf.aFontGlyphs3, rf.aFontGlyphs3Ext }, &[_][]u8{&font[3]}, 64, 128);
        DrawGlyphRegions(&[_][]rf.GLYPH{ rf.aFontGlyphs4, rf.aFontGlyphs4Ext }, &[_][]u8{&font[4]}, 64, 128);
        DumpGrey8toTGA(&font[0], 64, 128, "annodue/developer/fontraw0_mask.tga");
        DumpGrey8toTGA(&font[1], 64, 128, "annodue/developer/fontraw1_mask.tga");
        DumpGrey8toTGA(&font[2], 64, 128, "annodue/developer/fontraw2_mask.tga");
        DumpGrey8toTGA(&font[3], 64, 128, "annodue/developer/fontraw3_mask.tga");
        DumpGrey8toTGA(&font[4], 64, 128, "annodue/developer/fontraw4_mask.tga");

        DumpFontDefToCSV(&rf.aFontDef[0], 62, 15, "annodue/developer/fontdata0");
        DumpFontDefToCSV(&rf.aFontDef[1], 27, 0, "annodue/developer/fontdata1");
        DumpFontDefToCSV(&rf.aFontDef[2], 27, 0, "annodue/developer/fontdata2");
        DumpFontDefToCSV(&rf.aFontDef[3], 62, 15, "annodue/developer/fontdata3");
        DumpFontDefToCSV(&rf.aFontDef[4], 62, 15, "annodue/developer/fontdata4");
        DumpFontGlyphMapToCSV("annodue/developer/fontglyphmap");
    }
};

// ------------
// IO/devtools
// ------------

// FIXME: crashes if directory doesn't exist
// FIXME: handle FileAlreadyExists case (not sure best approach yet)
// FIXME: using bufferedwriter multiple times in the fn causes crash for some
// reason, even with defer-closing everything serially in advance??? so we use
// non-buffered for now; also, same issue with glyph map dump
fn DumpFontDefToCSV(font: *rf.FONT, g1_len: u8, g2_len: u8, filename_stem: []const u8) void {
    //assert(filename.len > 4);
    //assert(!std.mem.endsWith(u8, filename_stem, ".csv")); // we will add ".csv"
    var buf: [2048]u8 = undefined;

    { // MAIN FILE
        const filename = std.fmt.bufPrint(&buf, "{s}.csv", .{filename_stem}) catch unreachable;
        // FIXME: switch to exclusive mode and handle FileAlreadyExists
        const file = std.fs.cwd().createFile(filename, .{}) catch |e|
            PPanic("(DumpFontDefToCSV) create file: {s}", .{@errorName(e)});
        defer file.close();
        //var file_bw = std.io.bufferedWriter(file.writer());
        const file_w = file.writer();
        //defer _ = file_bw.flush() catch |e|
        //    PPanic("(DumpFontDefToCSV) flush: {s}", .{@errorName(e)});

        //_ = file_w.write("FONT\n") catch unreachable;
        file_w.print("\"Field\",\"Value\"\n", .{}) catch unreachable;
        file_w.print("\"0x00\",{d}\n", .{font._00}) catch unreachable;
        file_w.print("\"PageCount\",{d}\n", .{font._04_page_num}) catch unreachable;
        for (0..@intCast(font._04_page_num)) |i| {
            file_w.print(
                "\"Page[{d}]\",0x{X:0>6}\n",
                .{ i, @intFromPtr(font._08_page_list[i]) },
            ) catch unreachable;
        }
        file_w.print("\"LineHeight\",{d}\n", .{font._4C_line_height}) catch unreachable;
        file_w.print("\"MinChar\",0x{X:0>2}\n", .{font._5A_char_min}) catch unreachable;
        file_w.print("\"MaxChar\",0x{X:0>2}\n", .{font._5B_char_max}) catch unreachable;
        file_w.print("\"Glyphs\",0x{?X:0>6}\n", .{@intFromPtr(font._5C_glyphs)}) catch unreachable;
        file_w.print("\"GlyphsExt\",0x{?X:0>6}\n", .{@intFromPtr(font._60_glyphs_ext)}) catch unreachable;
    }

    // GLYPHS
    if (font._5C_glyphs) |glyphs| {
        const filename = std.fmt.bufPrint(&buf, "{s}_g.csv", .{filename_stem}) catch unreachable;
        const file = std.fs.cwd().createFile(filename, .{}) catch |e|
            PPanic("(DumpFontDefToCSV) create file: {s}", .{@errorName(e)});
        defer file.close();
        const file_w = file.writer();

        //_ = file_w.write("GLYPHS\n") catch unreachable;
        _ = file_w.write(
            "\"ID\",\"PID\",\"Adv\",\"OffY\",\"OffX\",\"X\",\"Y\",\"W\",\"H\",\"Ch\",\"CHex\"\n",
        ) catch unreachable;
        for (0..g1_len, font._5A_char_min..) |i, c| {
            const g = glyphs[i];
            file_w.print(
                \\"{d}","{d}","{d}","{d}","{d}","{d}","{d}","{d}","{d}","{s}{c}","0x{X:0>2}"
                \\
            , .{ i, g.PageID, g.Advance, g.OffY, g.OffX, g.TexX, g.TexY, g.TexW, g.TexH, if (c == 0x22) "\"" else "", @as(u8, @intCast(c)), c }) catch unreachable;
        }
    }

    // EXTENDED GLYPHS
    if (font._60_glyphs_ext) |glyphs| {
        const filename = std.fmt.bufPrint(&buf, "{s}_ge.csv", .{filename_stem}) catch unreachable;
        const file = std.fs.cwd().createFile(filename, .{}) catch |e|
            PPanic("(DumpFontDefToCSV) create file: {s}", .{@errorName(e)});
        defer file.close();
        const file_w = file.writer();

        _ = file_w.write(
            "\"ID\",\"PID\",\"Adv\",\"OffY\",\"OffX\",\"X\",\"Y\",\"W\",\"H\"\n",
        ) catch unreachable;
        for (0..g2_len) |i| {
            const g = glyphs[i];
            file_w.print(
                \\"{d}","{d}","{d}","{d}","{d}","{d}","{d}","{d}","{d}"
                \\
            , .{ i, g.PageID, g.Advance, g.OffY, g.OffX, g.TexX, g.TexY, g.TexW, g.TexH }) catch unreachable;
        }
    }
}

fn DumpFontGlyphMapToCSV(filename_stem: []const u8) void {
    //assert(filename.len > 4);
    //assert(!std.mem.endsWith(u8, filename_stem, ".csv")); // we will add ".csv"
    var buf: [2048]u8 = undefined;

    { // KEYS
        const filename = std.fmt.bufPrint(&buf, "{s}_k.csv", .{filename_stem}) catch unreachable;
        // FIXME: switch to exclusive mode and handle FileAlreadyExists
        const file = std.fs.cwd().createFile(filename, .{}) catch |e|
            PPanic("(DumpFontGlyphMapToCSV) create file: {s}", .{@errorName(e)});
        defer file.close();
        const file_w = file.writer();

        file_w.print("\"ValID\",\"Ch\",\"CHex\"\n", .{}) catch unreachable;
        for (rf.aFontExtGlyphMapKey, 150..) |k, c| {
            file_w.print("\"{d}\",\"{c}\",\"0x{X:0>2}\"\n", .{ k, @as(u8, @intCast(c)), c }) catch unreachable;
        }
    }

    { // VALUES
        const filename = std.fmt.bufPrint(&buf, "{s}_v.csv", .{filename_stem}) catch unreachable;
        const file = std.fs.cwd().createFile(filename, .{}) catch |e|
            PPanic("(DumpFontGlyphMapToCSV) create file: {s}", .{@errorName(e)});
        defer file.close();
        const file_w = file.writer();

        file_w.print("\"ExID\",\"Glyph\",\"GCh\",\"GCHex\"\n", .{}) catch unreachable;
        for (rf.aFontExtGlyphMapVal) |v| {
            file_w.print("\"{d}\",\"{d}\",\"{c}\",\"0x{X:0>2}\"\n", .{
                v._00_glyph1, v._01_glyph2, @as(u8, @intCast(v._01_glyph2)), v._01_glyph2,
            }) catch unreachable;
        }
    }
}

/// dump base font raw pixels to buffers, converting from Grey4 to Grey8
fn ExtractRawFontPagesToGrey8(buf: *[5][0x2000]u8) void {
    for (buf, 0..) |*b, i| {
        const page = &rf.aFontRawPageData[i];
        for (page, 0..) |px, j| {
            const px_i = j * 2;
            b[px_i + 0] = cf.ConvertMonoRGB(cf.G4, cf.G8, ra.hExtract4BPP(px, 0));
            b[px_i + 1] = cf.ConvertMonoRGB(cf.G4, cf.G8, ra.hExtract4BPP(px, 1));
        }
    }
}

// TODO: version which draws only one glyph?
/// draw glyphs as rectangular regions into Grey8 pixel buffers, matching each
/// glyph page id to the corresponding buffer. used to visualize where the glyph
/// extents lie on each page. assumes that glyph page ids will not exceed `2`.
/// @glyphs     sets of glyphs, typically fed from font's "std" and "ext" lists
/// @pages      grey8 pixel buffers corresponding to each page; eath bufer must
///              be @page_w * @page_h bytes long
fn DrawGlyphRegions(glyphs: []const []const rf.GLYPH, pages: []const []u8, page_w: i16, page_h: i16) void {
    for (pages) |p| assert(p.len == page_w * page_h);

    for (glyphs) |gs| {
        for (gs) |*g| {
            if (g.TexX == -1) continue; // not implemented in font data
            assert(@as(usize, @intCast(g.PageID)) <= pages.len); // FIXME: should this be an assert?
            const page = pages[@intCast(g.PageID)];
            var px_i: usize = @intCast(g.TexX + g.TexY * page_w);
            for (@intCast(g.TexY)..@intCast(g.TexY + g.TexH)) |y| {
                if (y >= page_h) continue;
                var px_j = px_i;
                for (@intCast(g.TexX)..@intCast(g.TexX + g.TexW)) |x| {
                    if (x >= page_w) continue;
                    page[px_j] = 0xFF;
                    px_j += 1;
                }
                px_i += @intCast(page_w);
            }
        }
    }
}

// FIXME: crashes if directory doesn't exist
// FIXME: handle FileAlreadyExists case (not sure best approach yet)
fn DumpGrey8toTGA(pixels: []const u8, width: u16, height: u16, filename: []const u8) void {
    assert(pixels.len == @as(u32, @intCast(width)) * height);
    assert(width > 0);
    assert(height > 0);
    assert(filename.len > 4);
    assert(std.mem.endsWith(u8, filename, ".tga"));

    // FIXME: switch to exclusive mode and handle FileAlreadyExists
    const file = std.fs.cwd().createFile(filename, .{}) catch |e|
        PPanic("(DumpGrey8toTGA) create file: {s}", .{@errorName(e)});
    defer file.close();
    var file_bw = std.io.bufferedWriter(file.writer());
    const file_w = file_bw.writer();
    defer _ = file_bw.flush() catch |e|
        PPanic("(DumpGrey8toTGA) flush: {s}", .{@errorName(e)});

    TGA.WriteGrey8(file_w, pixels, width, height) catch |e|
        PPanic("(DumpGrey8toTGA) write tga: {s}", .{@errorName(e)});
}

/// dumps pixel contents of a GIF file to an ARGB4444 pixel buffer, converting
/// the pixels to an alpha-masked white image. assumes the source is a greyscale
/// image suitable for converting to a mask.
/// @reader     GIF file reader with cursor at top of data (i.e. call gif.ReadHead first)
fn GIFBodyToAlphaARGB4444(gif: *GIF, arena: Allocator, reader: anytype, buf_o: []u16) !void {
    const buf_size = @as(usize, gif.CanvasW) * gif.CanvasH;
    var out = try std.ArrayList(u8).initCapacity(arena, buf_size * 4);
    defer out.deinit();
    const out_w = out.writer();

    try gif.ReadBody(arena, reader, out_w);

    var out_fbs = std.io.fixedBufferStream(out.items);
    const out_r = out_fbs.reader();
    for (0..buf_size) |i| {
        // FIXME: error handling?
        const color = out_r.readInt(u32, .Little) catch break; // no more colors
        // NOTE: output: shade goes into alpha, RGB must be 0xFFF
        // FIXME: this may be achievable without casting if cf behaviour is
        // changed, see note on ConvertMonoRGB A4->GA44 test case
        buf_o[i] = (@as(u16, @intCast(cf.ConvertMonoRGB(cf.RGBA8888, cf.G4, color))) << 12) | 0xFFF;
        // FIXME: with the following, grey value ends up in all four channels;
        // gif tests seem to confirm that alpha will be white with my decoder,
        // and similarly tests in color_format seem to indicate this will output
        // AGGG if given RGBA. there appears to be no other place the color is
        // transformed, so not sure why this drops the alpha
        //buf_o[i] = cf.ConvertMonoRGB(cf.RGBA8888, cf.ARGB4444, color);
    }
}

fn GIFTexturePath(arena: Allocator, filename: []const u8) ![]const u8 {
    const b_has_ext = std.mem.endsWith(u8, filename, ".gif") or std.mem.endsWith(u8, filename, ".GIF");
    const n = if (b_has_ext) filename[0 .. filename.len - 4] else filename;
    return std.fmt.allocPrint(arena, "annodue/textures/{s}.gif", .{n});
}

fn GIFCustomFontPath(arena: Allocator, filename: []const u8) ![]const u8 {
    const b_has_ext = std.mem.endsWith(u8, filename, ".gif") or std.mem.endsWith(u8, filename, ".GIF");
    const n = if (b_has_ext) filename[0 .. filename.len - 4] else filename;
    return std.fmt.allocPrint(arena, "annodue/custom/font/{s}.gif", .{n});
}

//------------------------------------------------------------------------------
// text clipping bugfix

var text_clip_fix_buf = std.mem.zeroes([128]u8);

// TODO: impl as settings toggle? to api-match other "bugfix toggles"
// TODO: document the bug somewhere; also may be an idea to document all the
// other bugs found in the game in a consolidated place
// NOTE: fix for following bug, which doesn't come up with stock fonts, but can
// cause rendering errors with custom fonts (e.g. profile select windowbox) due
// to larger glyph offsets
// - summary of bug
//   - after determining the current rendering character needs to clip (it partially
//     overlaps the clipping region boundary), the UV mapping of the texture is
//     adjusted with whole pixel values instead of UV-sized values
//   - affected region starts from instruction at 0x42DD08 (ebx set at 0x42DCC2)
//     and ends at 0x42DD8A
//   - let CurrentClipRegion be the Vec4i32 @ 0xE99750 containing the clip region at
//     screen-sized values (the size of the vbuffer, not the 640x480 virtual screen)
//   - let GlyphRegion be the local variables forming the Vec4i32 defining the
//     coordinates of the currently rendering glyph in the same screen-sized values
//   - let GlyphUVs be the local variables forming the Vec4f32 defining the UV
//     mapping of the currently rendering glyph, in range 0..1 of the whole texture
//   - bug: if edge E is clipping
//          EdgeDifference = CurrentClipRegion[E] - GlyphRegion[E]
//          new GlyphUVs[E] += EdgeDifference
//          (if case of x2/y2 edges, EdgeDifference terms reversed and output -=)
//   - fix: map EdgeDifference to UV range
//          ScreenToVirtualFactor = ScreenWidth/640 OR ScreenHeight/480
//              - precalculated @ esp+0x28+0x14, esp+0x28+0x18
//          VirtualPixelToUVFactor = 1/TextureW OR 1/TextureH (precalculated @ 0x4AC644, 0x4AC648)
//          EdgeDifference *= VirtualPixelToUVFactor*EdgeDifference/ScreenToVirtualFactorX
//   - other note: crude fix by skipping clipping entirely
//          at 0x42DCBC: jz 0042DD8A -> jmp 0042DD8A (+ nop leftover byte)
//   - relevant functions during research
//     - Text_DrawCharacter__42D990; see clipping codepaths
//     - Text_SetCurrentEntry1ClippingRegion__450310
//     - Text_FlushQueue1__450100
fn PatchTextClippingBug(apply: bool) void {
    if (apply) {
        var d: x86.Detour = undefined;
        d.Start(0x42DD08, 0x42DD8A, &text_clip_fix_buf);
        defer d.End();

        // get stable reference to esp, while storing ebp on the stack.
        // ebp contained pos_y2 (see instruction at 0x42DCB3), so the modified
        // stack copy will be propagated back to ebp during `reg_restore`.
        d.addr = x86.reg_save(d.addr, .esp, .ebp);
        defer d.addr = x86.reg_restore(d.addr, .esp, .ebp);

        // TODO: impl x86.PushSrc pointer types (r/m16, r/m32 (FF /6)) and use
        // in cdecl_call instead of manually managing args
        d.addr = x86.lea(d.addr, .eax, .ebp, 0x04 + 0x48); // uv_y2
        d.addr = x86.push(d.addr, .{ .r32 = .eax });
        d.addr = x86.lea(d.addr, .eax, .ebp, 0x04 + 0x40); // uv_x2
        d.addr = x86.push(d.addr, .{ .r32 = .eax });
        d.addr = x86.lea(d.addr, .eax, .ebp, 0x04 + 0x3C); // uv_y1
        d.addr = x86.push(d.addr, .{ .r32 = .eax });
        d.addr = x86.lea(d.addr, .eax, .ebp, 0x04 + 0x18); // uv_x1
        d.addr = x86.push(d.addr, .{ .r32 = .eax });
        d.addr = x86.lea(d.addr, .eax, .ebp, 0x00); // pos_y2
        d.addr = x86.push(d.addr, .{ .r32 = .eax });
        d.addr = x86.lea(d.addr, .eax, .ebp, 0x04 + 0x2C); // pos_x2
        d.addr = x86.push(d.addr, .{ .r32 = .eax });
        d.addr = x86.lea(d.addr, .eax, .ebp, 0x04 + 0x34); // pos_y1
        d.addr = x86.push(d.addr, .{ .r32 = .eax });
        d.addr = x86.lea(d.addr, .eax, .ebp, 0x04 + 0x14); // pos_x1
        d.addr = x86.push(d.addr, .{ .r32 = .eax });
        d.addr = x86.cdecl_call(d.addr, @intFromPtr(&ClipText), null);
        d.addr = x86.ADD(d.addr, .esp, null, .imm, 0x20);
    } else {
        // the original assembly bytes from the replaced code section
        _ = mem.write_bytes(0x42DD08, &[0x42DD8A - 0x42DD08]u8{
            0x3B, 0xD9, 0x7D, 0x1C, 0x2B, 0xCB, 0x8B, 0x5C, 0x24, 0x14, 0x89, 0x4C,
            0x24, 0x44, 0x03, 0xD9, 0xDB, 0x44, 0x24, 0x44, 0x89, 0x5C, 0x24, 0x14,
            0xD8, 0x44, 0x24, 0x18, 0xD9, 0x5C, 0x24, 0x18, 0x3B, 0xC2, 0x7D, 0x1C,
            0x2B, 0xD0, 0x8B, 0x44, 0x24, 0x34, 0x89, 0x54, 0x24, 0x44, 0x03, 0xC2,
            0xDB, 0x44, 0x24, 0x44, 0x89, 0x44, 0x24, 0x34, 0xD8, 0x44, 0x24, 0x40,
            0xD9, 0x5C, 0x24, 0x40, 0xA1, 0x58, 0x97, 0xE9, 0x00, 0x3B, 0xF0, 0x7E,
            0x1C, 0x2B, 0xF0, 0x8B, 0x44, 0x24, 0x2C, 0x89, 0x74, 0x24, 0x44, 0x2B,
            0xC6, 0xDB, 0x44, 0x24, 0x44, 0x89, 0x44, 0x24, 0x2C, 0xD8, 0x6C, 0x24,
            0x3C, 0xD9, 0x5C, 0x24, 0x3C, 0xA1, 0x5C, 0x97, 0xE9, 0x00, 0x3B, 0xF8,
            0x7E, 0x14, 0x2B, 0xF8, 0x89, 0x7C, 0x24, 0x44, 0x2B, 0xEF, 0xDB, 0x44,
            0x24, 0x44, 0xD8, 0x6C, 0x24, 0x48, 0xD9, 0x5C, 0x24, 0x48,
        });
    }
}

/// logic replacing the buggy clipping (fn_42D990). at the point this runs, the
/// game has already determined that the glyph is within the clipping region, and
/// just needs to check for partial overlap and update the quad pos and UVs
fn ClipText(
    pos_x1: *i32,
    pos_y1: *i32,
    pos_x2: *i32,
    pos_y2: *i32,
    uv_x1: *f32,
    uv_y1: *f32,
    uv_x2: *f32,
    uv_y2: *f32,
) callconv(.C) void {
    const hires_factor: f32 = if (rf.gbCurrentHiRes.* != 0) 0.5 else 1.0;
    const screen_w: f32 = @floatFromInt(rf.gScreenW.*);
    const screen_h: f32 = @floatFromInt(rf.gScreenH.*);
    const screen_scale_x = screen_w * @as(f32, @floatCast(rf.gScreenUnitScaleX.* * hires_factor));
    const screen_scale_y = screen_h * @as(f32, @floatCast(rf.gScreenUnitScaleY.* * hires_factor));

    if (pos_x1.* < rf.gCurrentClipRegion[0]) {
        const dif = rf.gCurrentClipRegion[0] - pos_x1.*;
        pos_x1.* = rf.gCurrentClipRegion[0];
        uv_x1.* += @as(f32, @floatFromInt(dif)) * rf.gFontPageUnitScaleX.* / screen_scale_x;
    }
    if (pos_y1.* < rf.gCurrentClipRegion[1]) {
        const dif = rf.gCurrentClipRegion[1] - pos_y1.*;
        pos_y1.* = rf.gCurrentClipRegion[1];
        uv_y1.* += @as(f32, @floatFromInt(dif)) * rf.gFontPageUnitScaleY.* / screen_scale_y;
    }
    if (pos_x2.* > rf.gCurrentClipRegion[2]) {
        const dif = pos_x2.* - rf.gCurrentClipRegion[2];
        pos_x2.* = rf.gCurrentClipRegion[2];
        uv_x2.* -= @as(f32, @floatFromInt(dif)) * rf.gFontPageUnitScaleX.* / screen_scale_x;
    }
    if (pos_y2.* > rf.gCurrentClipRegion[3]) {
        const dif = pos_y2.* - rf.gCurrentClipRegion[3];
        pos_y2.* = rf.gCurrentClipRegion[3];
        uv_y2.* -= @as(f32, @floatFromInt(dif)) * rf.gFontPageUnitScaleY.* / screen_scale_y;
    }
}

//------------------------------------------------------------------------------
// glyph adjustment

const GlyphFieldAdjustment = struct {
    const T = enum { Set, Add };
    const F = enum { Pg, Ad, OX, OY, TX, TY, TW, TH };
    t: T,
    f: F,
    v: i16,
};

// TODO: migrate to decl literal usage after updating zig version
inline fn GFA(
    t: GlyphFieldAdjustment.T,
    f: GlyphFieldAdjustment.F,
    v: i16,
) GlyphFieldAdjustment {
    return .{ .t = t, .f = f, .v = v };
}

const GlyphAdjustmentSet = struct { []const GlyphAdjustment, []const GlyphAdjustment };

const GlyphAdjustment = struct {
    i: usize,
    a: GlyphFieldAdjustment,

    /// adjust set of game GLYPHs
    pub fn AdjustSet(set: []rf.GLYPH, adjustments: []const GlyphAdjustment) void {
        for (adjustments) |adj| {
            var value: *i16 = switch (adj.a.f) {
                .Pg => &set[adj.i].PageID,
                .Ad => &set[adj.i].Advance,
                .OX => &set[adj.i].OffX,
                .OY => &set[adj.i].OffY,
                .TX => &set[adj.i].TexX,
                .TY => &set[adj.i].TexY,
                .TW => &set[adj.i].TexW,
                .TH => &set[adj.i].TexH,
            };
            switch (adj.a.t) {
                .Set => value.* = adj.a.v,
                .Add => value.* += adj.a.v,
            }
        }
    }

    /// adjust copied set of game GLYPHs
    pub fn AdjustSetClone(src: []const rf.GLYPH, dst: []rf.GLYPH, adjustments: []const GlyphAdjustment) void {
        assert(src.len == dst.len);
        @memcpy(dst, src);
        AdjustSet(dst, adjustments);
    }
};

//------------------------------------------------------------------------------
// glyph adjustment defs

// TODO: fix nomenclature: "core" -> "std" (to match racerlib)

const GLYPH_ADJUSTMENT_STOCK_TO_FIXED: [5]GlyphAdjustmentSet = .{
    .{ &ADJ_STOCK_TO_FIXED_FONT_0_CORE, &ADJ_STOCK_TO_FIXED_FONT_0_EXT },
    .{ &ADJ_STOCK_TO_FIXED_FONT_1_CORE, &.{} },
    .{ &ADJ_STOCK_TO_FIXED_FONT_2_CORE, &.{} },
    .{ &ADJ_STOCK_TO_FIXED_FONT_3_CORE, &ADJ_STOCK_TO_FIXED_FONT_3_EXT },
    .{ &ADJ_STOCK_TO_FIXED_FONT_4_CORE, &ADJ_STOCK_TO_FIXED_FONT_4_EXT },
};

const GLYPH_ADJUSTMENT_FIXED_TO_CUSTOM: [5]GlyphAdjustmentSet = .{
    .{ &ADJ_FIXED_TO_CUSTOM_FONT_0_CORE, &ADJ_FIXED_TO_CUSTOM_FONT_0_EXT },
    .{ &ADJ_FIXED_TO_CUSTOM_FONT_1_CORE, &.{} },
    .{ &ADJ_FIXED_TO_CUSTOM_FONT_2_CORE, &.{} },
    .{ &ADJ_FIXED_TO_CUSTOM_FONT_3_CORE, &ADJ_FIXED_TO_CUSTOM_FONT_3_EXT },
    .{ &ADJ_FIXED_TO_CUSTOM_FONT_4_CORE, &ADJ_FIXED_TO_CUSTOM_FONT_4_EXT },
};

const GLYPH_DISABLE = GFA(.Set, .TX, -1);

const ADJ_STOCK_TO_FIXED_FONT_0_CORE = [_]GlyphAdjustment{
    .{ .i = 1, .a = GLYPH_DISABLE },
    .{ .i = 2, .a = GFA(.Add, .OX, 5) },
    .{ .i = 3, .a = GLYPH_DISABLE },
    .{ .i = 4, .a = GLYPH_DISABLE },
    .{ .i = 7, .a = GFA(.Add, .OX, 5) },
    .{ .i = 8, .a = GLYPH_DISABLE },
    .{ .i = 9, .a = GLYPH_DISABLE },
    .{ .i = 10, .a = GLYPH_DISABLE },
    .{ .i = 11, .a = GFA(.Add, .Ad, 3) },
    .{ .i = 12, .a = GLYPH_DISABLE },
    .{ .i = 14, .a = GLYPH_DISABLE },
    .{ .i = 12, .a = GFA(.Add, .Ad, 3) },
    .{ .i = 14, .a = GFA(.Add, .Ad, 5) },
    .{ .i = 15, .a = GFA(.Add, .OY, -1) },
    .{ .i = 27, .a = GLYPH_DISABLE },
    .{ .i = 27, .a = GFA(.Add, .Ad, 5) }, // TODO: tweak against real text (use fixed new atlas)
    .{ .i = 28, .a = GLYPH_DISABLE },
    .{ .i = 30, .a = GLYPH_DISABLE },
    .{ .i = 35, .a = GFA(.Add, .OX, -1) },
    .{ .i = 51, .a = GFA(.Add, .OX, -1) },
    .{ .i = 57, .a = GFA(.Add, .OX, -1) },
};

const ADJ_STOCK_TO_FIXED_FONT_0_EXT = [_]GlyphAdjustment{
    .{ .i = 1, .a = GLYPH_DISABLE },
    .{ .i = 2, .a = GLYPH_DISABLE },
    .{ .i = 6, .a = GFA(.Add, .OX, 1) },
    .{ .i = 7, .a = GFA(.Add, .OX, 1) },
    .{ .i = 8, .a = GFA(.Add, .OX, 1) },
    .{ .i = 9, .a = GFA(.Add, .OX, 2) },
    .{ .i = 10, .a = GFA(.Add, .OX, 1) },
    .{ .i = 11, .a = GFA(.Add, .OX, 2) },
    .{ .i = 13, .a = GFA(.Add, .OY, -2) },
    .{ .i = 14, .a = GFA(.Add, .OY, -2) },
};

const ADJ_STOCK_TO_FIXED_FONT_1_CORE = [_]GlyphAdjustment{
    .{ .i = 1, .a = GLYPH_DISABLE },
    .{ .i = 3, .a = GLYPH_DISABLE },
    .{ .i = 4, .a = GLYPH_DISABLE },
    .{ .i = 7, .a = GLYPH_DISABLE },
    .{ .i = 8, .a = GLYPH_DISABLE },
    .{ .i = 9, .a = GLYPH_DISABLE },
    .{ .i = 10, .a = GLYPH_DISABLE },
    .{ .i = 12, .a = GLYPH_DISABLE },
    .{ .i = 13, .a = GLYPH_DISABLE },
    .{ .i = 14, .a = GLYPH_DISABLE },
    .{ .i = 14, .a = GFA(.Add, .Ad, 5) },
    .{ .i = 15, .a = GLYPH_DISABLE },
};

const ADJ_STOCK_TO_FIXED_FONT_2_CORE = [_]GlyphAdjustment{
    .{ .i = 1, .a = GLYPH_DISABLE },
    .{ .i = 3, .a = GLYPH_DISABLE },
    .{ .i = 4, .a = GLYPH_DISABLE },
    .{ .i = 7, .a = GLYPH_DISABLE },
    .{ .i = 8, .a = GLYPH_DISABLE },
    .{ .i = 9, .a = GLYPH_DISABLE },
    .{ .i = 10, .a = GLYPH_DISABLE },
    .{ .i = 12, .a = GLYPH_DISABLE },
    .{ .i = 13, .a = GLYPH_DISABLE },
    .{ .i = 23, .a = GFA(.Add, .OX, -1) },
};

const ADJ_STOCK_TO_FIXED_FONT_3_CORE = [_]GlyphAdjustment{
    .{ .i = 3, .a = GLYPH_DISABLE },
    .{ .i = 4, .a = GLYPH_DISABLE },
    .{ .i = 8, .a = GLYPH_DISABLE },
    .{ .i = 9, .a = GLYPH_DISABLE },
    .{ .i = 11, .a = GFA(.Add, .TY, 1) },
    .{ .i = 12, .a = GFA(.Add, .OY, -2) },
    .{ .i = 13, .a = GFA(.Add, .OX, -1) },
    .{ .i = 17, .a = GFA(.Add, .OX, 1) },
    .{ .i = 17, .a = GFA(.Add, .TX, -1) },
    .{ .i = 26, .a = GFA(.Add, .OY, -1) },
    .{ .i = 28, .a = GLYPH_DISABLE },
    .{ .i = 30, .a = GLYPH_DISABLE },
};

const ADJ_STOCK_TO_FIXED_FONT_3_EXT = [_]GlyphAdjustment{
    // pound (currency); this one may be intentional, overlaps 'L'
    //.{ .i = 2, .a = GLYPH_DISABLE },
    .{ .i = 3, .a = GFA(.Set, .TX, 20) },
    .{ .i = 4, .a = GFA(.Set, .TX, 12) },
};

const ADJ_STOCK_TO_FIXED_FONT_4_CORE = [_]GlyphAdjustment{
    .{ .i = 2, .a = GFA(.Add, .OY, 1) },
    .{ .i = 2, .a = GFA(.Add, .TH, -2) },
    .{ .i = 7, .a = GFA(.Add, .OY, 1) },
    .{ .i = 7, .a = GFA(.Add, .TH, -2) },
    .{ .i = 10, .a = GLYPH_DISABLE },
    .{ .i = 12, .a = GFA(.Add, .TH, -2) },
    .{ .i = 14, .a = GFA(.Set, .TX, 1) },
    .{ .i = 14, .a = GFA(.Set, .TY, 25) },
    .{ .i = 14, .a = GFA(.Set, .TW, 3) },
    .{ .i = 17, .a = GFA(.Add, .OX, -1) },
    .{ .i = 20, .a = GFA(.Add, .OX, -1) },
    .{ .i = 23, .a = GFA(.Add, .OX, 1) },
    .{ .i = 28, .a = GLYPH_DISABLE },
    .{ .i = 30, .a = GLYPH_DISABLE },
    .{ .i = 61, .a = GFA(.Add, .OX, 1) },
    .{ .i = 61, .a = GFA(.Add, .TX, -1) },
    .{ .i = 61, .a = GFA(.Add, .TW, 1) },
};

const ADJ_STOCK_TO_FIXED_FONT_4_EXT = [_]GlyphAdjustment{
    .{ .i = 1, .a = GFA(.Set, .TX, 27) },
    .{ .i = 1, .a = GFA(.Set, .TY, 21) },
    .{ .i = 2, .a = GLYPH_DISABLE },
    .{ .i = 3, .a = GFA(.Add, .OY, 1) },
    .{ .i = 4, .a = GFA(.Add, .OY, 1) },
    .{ .i = 9, .a = GFA(.Add, .OX, 2) },
    .{ .i = 11, .a = GFA(.Add, .OX, 1) },
    .{ .i = 13, .a = GFA(.Add, .OY, -1) },
    .{ .i = 14, .a = GFA(.Add, .OY, -1) },
};

/// t* values are absolute, o* values are relative
///                                   id     tx   ty   tw   th   ox   oy
const BatchGlyphAdjustment = struct { usize, i16, i16, i16, i16, i16, i16 };

/// custom font format helper for batch generation of glyph adjustments
/// @p      indices of glyphs to set to page 0 (format uses one page for all fonts)
/// @a      glyph adjustment defs in batch format
inline fn CGA(
    comptime p: []const usize,
    comptime a: []const BatchGlyphAdjustment,
) [p.len + a.len * 6]GlyphAdjustment {
    var ga = std.mem.zeroes([p.len + a.len * 6]GlyphAdjustment);
    for (p, 0..) |g, i| {
        ga[i] = .{ .i = g, .a = GFA(.Set, .Pg, 0) };
    }
    for (a, 0..) |g, i| {
        ga[p.len + i * 6 + 0] = .{ .i = g[0], .a = GFA(.Set, .TX, g[1]) };
        ga[p.len + i * 6 + 1] = .{ .i = g[0], .a = GFA(.Set, .TY, g[2]) };
        ga[p.len + i * 6 + 2] = .{ .i = g[0], .a = GFA(.Set, .TW, g[3]) };
        ga[p.len + i * 6 + 3] = .{ .i = g[0], .a = GFA(.Set, .TH, g[4]) };
        ga[p.len + i * 6 + 4] = .{ .i = g[0], .a = GFA(.Add, .OX, g[5]) };
        ga[p.len + i * 6 + 5] = .{ .i = g[0], .a = GFA(.Add, .OY, g[6]) };
    }
    return ga;
}

const ADJ_FIXED_TO_CUSTOM_FONT_0_CORE = CGA(&[_]usize{
    2,  7,  13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
    23, 24, 25, 26, 31, 52, 53, 54, 55, 56, 57, 58,
}, &[_]BatchGlyphAdjustment{
    .{ 2, 46, 106, 11, 9, 2, 2 }, // "
    .{ 7, 57, 106, 11, 9, 2, 2 }, // '
    .{ 11, 57, 55, 17, 24, 2, 8 }, // +
    .{ 12, 33, 76, 12, 14, 2, 1 }, // ,
    .{ 13, 45, 55, 12, 24, 2, 2 }, // -
    .{ 14, 22, 76, 11, 14, 2, 1 }, // .
    .{ 15, 32, 90, 14, 25, 2, 5 }, // /
    .{ 26, 22, 52, 11, 24, 2, -3 }, // :
    .{ 27, 33, 52, 12, 24, 2, 4 }, // ;
    .{ 31, 70, 79, 17, 25, 2, 2 }, // ?
    .{ 16, 74, 52, 18, 27, 2, 2 }, // 0
    .{ 17, 92, 52, 18, 27, 4, 2 },
    .{ 18, 110, 52, 18, 27, 3, 2 },
    .{ 19, 128, 52, 18, 27, 2, 2 },
    .{ 20, 146, 52, 18, 27, 2, 2 },
    .{ 21, 164, 52, 18, 27, 2, 2 },
    .{ 22, 182, 52, 18, 27, 2, 2 },
    .{ 23, 200, 52, 18, 27, 3, 2 },
    .{ 24, 218, 52, 18, 27, 2, 2 },
    .{ 25, 236, 52, 18, 27, 3, 2 }, // 9
    .{ 33, 0, 0, 18, 26, 2, 2 }, // A
    .{ 34, 18, 0, 19, 26, 2, 2 },
    .{ 35, 37, 0, 19, 26, 2, 2 },
    .{ 36, 55, 0, 18, 26, 2, 2 },
    .{ 37, 73, 0, 18, 26, 2, 2 },
    .{ 38, 91, 0, 18, 26, 2, 2 },
    .{ 39, 109, 0, 18, 26, 2, 2 },
    .{ 40, 127, 0, 19, 26, 2, 2 },
    .{ 41, 146, 0, 18, 26, 4, 2 },
    .{ 42, 164, 0, 18, 26, 3, 2 },
    .{ 43, 182, 0, 20, 26, 2, 2 },
    .{ 44, 202, 0, 18, 26, 4, 2 },
    .{ 45, 220, 0, 22, 26, 2, 2 },
    .{ 46, 0, 26, 19, 26, 2, 2 },
    .{ 47, 19, 26, 18, 26, 2, 2 },
    .{ 48, 37, 26, 18, 26, 2, 2 },
    .{ 49, 55, 26, 18, 29, 2, 2 },
    .{ 50, 73, 26, 19, 26, 2, 2 },
    .{ 51, 92, 26, 18, 26, 2, 2 },
    .{ 52, 110, 26, 18, 26, 3, 2 },
    .{ 53, 128, 26, 19, 26, 2, 2 },
    .{ 54, 147, 26, 18, 26, 2, 2 },
    .{ 55, 165, 26, 24, 26, 2, 2 },
    .{ 56, 189, 26, 19, 26, 2, 2 },
    .{ 57, 208, 26, 18, 26, 3, 2 },
    .{ 58, 226, 26, 18, 26, 2, 2 }, // Z
});

const ADJ_FIXED_TO_CUSTOM_FONT_0_EXT = CGA(&[_]usize{
    0,  1,  2,  3, 4, 5, 6, 7, 8, 9, 10, 11,
    12, 13, 14,
}, &[_]BatchGlyphAdjustment{
    .{ 3, 0, 94, 16, 16, 2, 2 }, // superscript a
    .{ 4, 16, 94, 16, 16, 2, 2 }, // superscript o
    .{ 5, 70, 79, 17, 25, 2, 2 }, // inverted ?
    .{ 6, 113, 79, 11, 9, 2, 2 }, // grave
    .{ 7, 124, 79, 11, 9, 2, 2 }, // acute
    .{ 8, 135, 79, 13, 9, 2, 2 }, // circumflex
    .{ 9, 148, 79, 14, 8, 2, 2 }, // tilde
    .{ 10, 99, 79, 14, 10, 2, 2 }, // diaeresis
    .{ 11, 87, 79, 12, 11, 2, 2 }, // cedilla
    .{ 12, 46, 79, 24, 27, 2, 2 }, // szling
    .{ 13, 0, 52, 22, 21, 2, 2 }, // <<
    .{ 14, 0, 73, 22, 21, 2, 2 }, // >>
});

const ADJ_FIXED_TO_CUSTOM_FONT_1_CORE = CGA(&[_]usize{}, &[_]BatchGlyphAdjustment{
    .{ 14, 22, 76, 11, 14, 2, 1 }, // .
    .{ 26, 22, 52, 11, 24, 2, -3 }, // :
    .{ 16, 74, 52, 18, 27, 2, 2 }, // 0
    .{ 17, 92, 52, 18, 27, 4, 2 },
    .{ 18, 110, 52, 18, 27, 3, 2 },
    .{ 19, 128, 52, 18, 27, 2, 2 },
    .{ 20, 146, 52, 18, 27, 2, 2 },
    .{ 21, 164, 52, 18, 27, 2, 2 },
    .{ 22, 182, 52, 18, 27, 2, 2 },
    .{ 23, 200, 52, 18, 27, 3, 2 },
    .{ 24, 218, 52, 18, 27, 2, 2 },
    .{ 25, 236, 52, 18, 27, 3, 2 }, // 9
});

const ADJ_FIXED_TO_CUSTOM_FONT_2_CORE = CGA(&[_]usize{}, &[_]BatchGlyphAdjustment{
    .{ 14, 84, 105, 9, 10, 2, 3 }, // .
    .{ 15, 102, 96, 14, 19, 2, 2 }, // /
    .{ 26, 93, 99, 9, 16, 2, -1 }, // :
    .{ 16, 116, 97, 14, 18, 2, 2 }, // 0
    .{ 17, 130, 97, 14, 18, 3, 2 },
    .{ 18, 144, 97, 14, 18, 2, 2 },
    .{ 19, 158, 97, 14, 18, 2, 2 },
    .{ 20, 172, 97, 14, 18, 2, 2 },
    .{ 21, 186, 97, 14, 18, 2, 2 },
    .{ 22, 200, 97, 14, 18, 2, 2 },
    .{ 23, 214, 97, 14, 18, 2, 2 },
    .{ 24, 228, 97, 14, 18, 2, 2 },
    .{ 25, 242, 97, 14, 18, 2, 2 }, // 9
});

const ADJ_FIXED_TO_CUSTOM_FONT_3_CORE = CGA(&[_]usize{}, &[_]BatchGlyphAdjustment{
    .{ 2, 65, 149, 9, 8, 3, 3 }, // "
    .{ 7, 74, 149, 9, 8, 3, 3 }, // '
    .{ 10, 226, 133, 13, 15, 2, 2 }, // +
    .{ 11, 241, 133, 15, 15, 2, 2 }, // *
    .{ 13, 97, 143, 7, 9, 1, 4 }, // -
    .{ 15, 202, 133, 12, 15, 2, 2 }, // /
    .{ 60, 214, 133, 12, 15, 2, 2 }, // \
    .{ 14, 69, 143, 7, 6, 3, 2 }, // .
    .{ 12, 76, 143, 7, 6, 2, 2 }, // ,
    .{ 26, 83, 143, 7, 9, 2, 2 }, // :
    .{ 27, 90, 143, 7, 9, 2, 2 }, // ;
    .{ 59, 128, 143, 7, 11, 2, 2 }, // [
    .{ 61, 135, 143, 7, 11, 2, 2 }, // ]
    .{ 1, 104, 143, 7, 11, 2, 2 }, // !
    .{ 31, 118, 143, 10, 11, 2, 2 }, // ?
    .{ 16, 65, 132, 11, 11, 2, 2 }, // 0
    .{ 17, 76, 132, 11, 11, 2, 2 },
    .{ 18, 87, 132, 11, 11, 2, 2 },
    .{ 19, 98, 132, 11, 11, 2, 2 },
    .{ 20, 109, 132, 11, 11, 2, 2 },
    .{ 21, 120, 132, 11, 11, 2, 2 },
    .{ 22, 131, 132, 11, 11, 2, 2 },
    .{ 23, 142, 132, 11, 11, 2, 2 },
    .{ 24, 153, 132, 11, 11, 2, 2 },
    .{ 25, 164, 132, 11, 11, 2, 2 }, // 9
    .{ 33, 0, 121, 12, 11, 2, 2 }, // A
    .{ 34, 12, 121, 12, 11, 2, 2 },
    .{ 35, 24, 121, 12, 11, 2, 2 },
    .{ 36, 36, 121, 12, 11, 2, 2 },
    .{ 37, 48, 121, 12, 11, 3, 2 },
    .{ 38, 60, 121, 12, 11, 2, 2 },
    .{ 39, 72, 121, 12, 11, 2, 2 },
    .{ 40, 84, 121, 12, 11, 2, 2 },
    .{ 41, 96, 121, 12, 11, 3, 2 },
    .{ 42, 108, 121, 12, 11, 3, 2 },
    .{ 43, 120, 121, 12, 11, 2, 2 },
    .{ 44, 132, 121, 12, 11, 3, 2 },
    .{ 45, 144, 121, 13, 11, 2, 2 },
    .{ 46, 157, 121, 13, 11, 2, 2 },
    .{ 47, 170, 121, 12, 11, 2, 2 },
    .{ 48, 182, 121, 12, 11, 2, 2 },
    .{ 49, 194, 121, 12, 12, 2, 2 },
    .{ 50, 206, 121, 12, 11, 2, 2 },
    .{ 51, 218, 121, 12, 11, 2, 2 },
    .{ 52, 230, 121, 12, 11, 2, 2 },
    .{ 53, 242, 121, 12, 11, 2, 2 },
    .{ 54, 0, 132, 12, 11, 2, 2 },
    .{ 55, 12, 132, 15, 11, 2, 2 },
    .{ 56, 27, 132, 12, 11, 2, 2 },
    .{ 57, 39, 132, 12, 11, 2, 2 },
    .{ 58, 51, 132, 12, 11, 2, 2 }, // Z
});

const ADJ_FIXED_TO_CUSTOM_FONT_3_EXT = CGA(&[_]usize{}, &[_]BatchGlyphAdjustment{
    .{ 1, 111, 143, 7, 11, 2, 2 }, // inverted !
    .{ 2, 144, 144, 10, 11, 2, 2 }, // pound (currency)
    .{ 3, 154, 144, 11, 11, 2, 2 }, // superscript a
    .{ 4, 166, 144, 12, 11, 1, 2 }, // superscript o
    .{ 5, 118, 143, 10, 11, 2, 2 }, // inverted ?
    .{ 6, 21, 144, 9, 8, 2, 2 }, // grave
    .{ 7, 30, 144, 9, 8, 2, 2 }, // acute
    .{ 8, 39, 144, 11, 8, 2, 2 }, // circumflex
    .{ 9, 50, 144, 13, 8, 2, 2 }, // tilde
    .{ 10, 10, 144, 11, 7, 2, 2 }, // diaeresis
    .{ 11, 0, 144, 10, 8, 2, 2 }, // cedilla
    .{ 12, 190, 133, 12, 15, 2, 2 }, // szling
    .{ 13, 177, 133, 13, 11, 2, 2 }, // <<
    .{ 14, 177, 144, 13, 11, 2, 2 }, // >>
});

const ADJ_FIXED_TO_CUSTOM_FONT_4_CORE = CGA(&[_]usize{}, &[_]BatchGlyphAdjustment{
    .{ 2, 74, 180, 9, 7, 3, 3 }, // "
    .{ 7, 83, 180, 9, 7, 3, 3 }, // '
    .{ 13, 106, 179, 7, 9, 2, 2 }, // -
    .{ 15, 151, 179, 9, 11, 3, 3 }, // /
    .{ 14, 92, 172, 7, 7, 2, 3 }, // .
    .{ 12, 99, 172, 7, 7, 2, 3 }, // ,
    .{ 26, 92, 179, 7, 9, 3, 1 }, // :
    .{ 27, 99, 179, 7, 9, 3, 1 }, // ;
    .{ 8, 135, 179, 8, 11, 3, 3 }, // (
    .{ 9, 143, 179, 8, 11, 2, 3 }, // )
    .{ 59, 160, 179, 7, 11, 2, 3 }, // [
    .{ 61, 167, 179, 7, 11, 2, 3 }, // ]
    .{ 3, 239, 159, 13, 9, 2, 2 }, // (substituted) trademark
    .{ 4, 240, 168, 12, 12, 2, 2 }, // (substituted) copyright
    .{ 5, 240, 180, 12, 12, 2, 2 }, // (substituted) registered
    .{ 1, 113, 179, 7, 11, 3, 3 }, // !
    .{ 31, 127, 179, 8, 11, 2, 3 }, // ?
    .{ 16, 0, 171, 9, 9, 2, 2 }, // 0
    .{ 17, 9, 171, 9, 9, 2, 2 },
    .{ 18, 18, 171, 9, 9, 2, 2 },
    .{ 19, 27, 171, 9, 9, 2, 2 },
    .{ 20, 36, 171, 9, 9, 2, 2 },
    .{ 21, 45, 171, 9, 9, 2, 2 },
    .{ 22, 54, 171, 9, 9, 2, 2 },
    .{ 23, 63, 171, 9, 9, 2, 2 },
    .{ 24, 72, 171, 9, 9, 2, 2 },
    .{ 25, 81, 171, 9, 9, 2, 2 }, // 9
    .{ 33, 0, 162, 9, 9, 2, 2 }, // A
    .{ 34, 9, 162, 9, 9, 2, 2 },
    .{ 35, 18, 162, 9, 9, 2, 2 },
    .{ 36, 27, 162, 9, 9, 2, 2 },
    .{ 37, 36, 162, 9, 9, 2, 2 },
    .{ 38, 45, 162, 9, 9, 2, 2 },
    .{ 39, 54, 162, 9, 9, 2, 2 },
    .{ 40, 63, 162, 9, 9, 2, 2 },
    .{ 41, 72, 162, 9, 9, 2, 2 },
    .{ 42, 81, 162, 9, 9, 3, 2 },
    .{ 43, 90, 162, 9, 9, 2, 2 },
    .{ 44, 99, 162, 9, 9, 2, 2 },
    .{ 45, 108, 162, 10, 9, 2, 2 },
    .{ 46, 118, 162, 9, 9, 2, 2 },
    .{ 47, 127, 162, 9, 9, 2, 2 },
    .{ 48, 136, 162, 9, 9, 2, 2 },
    .{ 49, 145, 162, 9, 10, 2, 2 },
    .{ 50, 154, 162, 9, 9, 2, 2 },
    .{ 51, 163, 162, 9, 9, 2, 2 },
    .{ 52, 172, 162, 9, 9, 2, 2 },
    .{ 53, 181, 162, 9, 9, 2, 2 },
    .{ 54, 190, 162, 9, 9, 2, 2 },
    .{ 55, 199, 162, 11, 9, 2, 2 },
    .{ 56, 210, 162, 9, 9, 2, 2 },
    .{ 57, 219, 162, 9, 9, 2, 2 },
    .{ 58, 228, 162, 9, 9, 2, 2 }, // Z
});

const ADJ_FIXED_TO_CUSTOM_FONT_4_EXT = CGA(&[_]usize{}, &[_]BatchGlyphAdjustment{
    .{ 1, 120, 179, 7, 11, 3, 3 }, // inverted !
    .{ 3, 177, 179, 12, 11, 2, 2 }, // superscript a
    .{ 4, 189, 179, 12, 11, 2, 2 }, // superscript o
    .{ 5, 127, 179, 8, 11, 2, 2 }, // inverted ?
    .{ 6, 20, 180, 10, 8, 2, 2 }, // grave
    .{ 7, 30, 180, 10, 8, 2, 2 }, // acute
    .{ 8, 40, 180, 11, 8, 2, 2 }, // circumflex
    .{ 9, 51, 180, 11, 8, 2, 2 }, // tilde
    .{ 10, 11, 180, 9, 7, 2, 2 }, // dieresis
    .{ 11, 0, 180, 11, 8, 2, 2 }, // cedilla
    .{ 12, 227, 179, 11, 13, 2, 2 }, // szling
    .{ 13, 201, 179, 13, 11, 2, 2 }, // <<
    .{ 14, 214, 179, 13, 11, 2, 2 }, // >>
});

//------------------------------------------------------------------------------
// custom stuff workspace

// FIXME: to organize/streamline; random stuff used to work through feature dev

// FIXME: relocate, for testing
const GIF = @import("util/gif.zig");
const cf = @import("util/color_format.zig");

var fonts_loaded: bool = false;
var fonts_active: bool = false;
var fonts_custom_active: bool = false;

/// holding font for (unused) stock fixed font
var font_stock_fixed: CustomFont = undefined;

/// holding font for stock fixed font in user-custom format
var font_stock_custom: CustomFont = undefined;

// TODO: hashmap-based collection of font structs, so that multiple can be loaded
//  at the same time to avoid load lag every time the font is switched in future
/// holding font for user-chosen custom font
var font_custom: CustomFont = undefined;

const font_test_strings: [7][4][55:0]u8 = blk: {
    var test_text = std.mem.zeroes([100]u8);
    // 62 'normal' characters starting at 0x20
    for (0..62) |i| test_text[i] = ' ' + i;
    // 15 'extended' characters accessed from following ascii codes:
    // 0xEn onwards can be skipped, same as previous -> 33 items
    const test_chars_ext = [_]u8{
        0x99, 0xA1, 0xA3, 0xAA, 0xAB, 0xBA, 0xBB, 0xBF, 0xC0, 0xC1, 0xC2, 0xC3,
        0xC4, 0xC7, 0xC8, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF, 0xD1, 0xD2,
        0xD3, 0xD4, 0xD5, 0xD6, 0xD9, 0xDA, 0xDB, 0xDC, 0xDF, 0xE1, 0xE2, 0xE3,
        0xE4, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF, 0xF1, 0xF2,
        0xF3, 0xF4, 0xF5, 0xF6, 0xF9, 0xFA, 0xFB, 0xFC,
    };
    @memcpy(test_text[62..95], test_chars_ext[0..33]);

    var buf = std.mem.zeroes([7][4][55:0]u8);
    for (0..7) |i| {
        var pre = [5]u8{ '~', 'F', '0' + i, '~', 's' };
        for (0..2) |j| {
            @memcpy(buf[i][j][0..5], &pre);
            @memcpy(buf[i][j][5..55], test_text[j * 50 .. (j + 1) * 50]);
        }
    }
    break :blk buf;
};

// TODO: tests for de/serialization
// FIXME: remove needless fields that could be function args, e.g. GlyphAdjustments;
//  also do similar simplification pass on other code
const CustomFont = struct {
    Name: [127:0]u8,
    FontTable: [7]?*rf.FONT,
    Fonts: [5]rf.FONT,
    Pages: [5]CustomPage,
    PageSize: struct { w: u16, h: u16 },
    Glyphs: [5]CustomGlyphs,
    Mode: Structure,
    bPagesLoadedToGame: bool = false,

    const Structure = enum(u8) { Source, Custom };

    pub const GlyphBinDeserializationError = error{VersionMismatch};
    pub const GLYPH_BIN_VERSION: u32 = 1;

    pub fn Init(font: *CustomFont, mode: Structure, page_w: u16, page_h: u16, name: []const u8) void {
        font.* = std.mem.zeroes(CustomFont);

        assert(name.len <= 127);
        _ = std.fmt.bufPrintZ(&font.Name, "{s}", .{name}) catch unreachable;

        font.Mode = mode;
        font.PageSize = .{ .w = page_w, .h = page_h };
        // TODO: after migrating to new zig version, check if these pointer mappings can
        //  be done implicitly (cant remember if cross-pointer init stuff is comptime only)
        font.FontTable = .{
            &font.Fonts[3], &font.Fonts[2], &font.Fonts[1], &font.Fonts[2],
            &font.Fonts[4], &font.Fonts[3], &font.Fonts[0],
        };
        font.bPagesLoadedToGame = false;
    }

    // TODO: merge with CloneGlyphs? does this even need to be a separate step?
    //  how much of the stuff in FontLoad even needs to be individual steps?
    // TODO: fix font page number field; need to think about how to keep it
    // up to date overall
    pub fn CloneFonts(self: *CustomFont, defs: *const [5]rf.FONT, b_keep_pages: bool) void {
        @memcpy(&self.Fonts, defs);
        if (b_keep_pages) return;

        for (&self.Fonts) |*f| {
            f._08_page_list = std.mem.zeroes(@TypeOf(f._08_page_list));
        }
    }

    // TODO: ?? assert each glyph adjustment set only contains glyph ids that do
    //  not exceed the glyph counts already specified in the `glyphs` structs?
    /// clone glyphs and initialize by adjusting cloned glyphs
    pub fn GlyphsFromAdjustment(
        self: *CustomFont,
        glyphs: *const [5]CustomGlyphs,
        adjustments: *const [5]GlyphAdjustmentSet,
    ) void {
        @memcpy(&self.Glyphs, glyphs);
        for (&self.Fonts, &self.Glyphs, adjustments) |*f, *g, *ga| {
            f._5C_glyphs = if (g.StdSize == 0) null else &g.Std;
            f._60_glyphs_ext = if (g.ExtSize == 0) null else &g.Ext;
            GlyphAdjustment.AdjustSet(&g.Std, ga[0]);
            GlyphAdjustment.AdjustSet(&g.Ext, ga[1]);
        }
    }

    // TODO: proper error handling rather than just insta crashing
    // TODO: ?? assert each glyph binary set contains the same amount of glyphs
    //  already specified in the `glyphs` structs?
    // FIXME: is the GlyphsFromAdgjustment-style memcpy even needed here? do the
    //  `glyphs` have wrong length values and/or is there a mismatch of values on
    //  the `rf.FONT`s now that the adjustments have messed with which glyphs are
    //  usable? (same question for the adjustment-based counterpart). update:
    //  current usage implicitly matches the numbers already specified by the game
    //  for the sake of keeping it consistent, so currently this isn't an issue,
    //  but it may become an issue in future when expanding on the custom font
    //  capabilities and allowing users to fully specify custom fonts with
    //  unrestricted glyphs; in particular, the sizes imply a particular range of
    //  ascii indices on the game font struct, which are currently not updated to
    //  reflect the contents of CustomGlyphs, and CustomGlyphs itself doesn't
    //  track the starting character of the range. also, for now memcpy has been
    //  removed, since the CustomGlyphs deserializer overwrites all fields.
    /// clone glyphs and initialize by loading glyph data directly from binary
    /// data dumped with GlyphBinDump
    fn GlyphsFromBin(self: *CustomFont, data: []const u8) void {
        var data_fbs = std.io.fixedBufferStream(data);
        self.GlyphBinDeserialize(data_fbs.reader()) catch |e|
            PPanic("(GlyphsFromBin) deserialize glyphs: {s}", .{@errorName(e)});

        for (&self.Fonts, &self.Glyphs) |*f, *g| {
            f._5C_glyphs = if (g.StdSize == 0) null else &g.Std;
            f._60_glyphs_ext = if (g.ExtSize == 0) null else &g.Ext;
        }
    }

    // TODO: error checking for whether the game actually returns a texture
    //  pointer, whether the user actually supplied enough pages, etc.
    // TODO: potentially set the page counts from here based on mode
    // FIXME: potential use-after-free, double-free, etc. if sharing materials
    //  between custom fonts and not tracking ownership; probably need a better
    //  way of referencing materials in CustomFont to mitigate/eliminate this
    //  risk architecturally. maybe track whether the game is holding references
    //  to our pages on CustomPage directly? maybe CustomPage-es should be tracked
    //  independently via handles and ref counted? incidentally, that would be
    //  dangerously close to a straight up "load/unload texture" api
    /// creates a new game material from the raw pixel data, and stores the game
    /// references. not needed if using an existing material, such as the one
    /// the game loads normally.
    pub fn LoadPagesToGame(self: *CustomFont, pixeldata: []u16) void {
        if (self.bPagesLoadedToGame) return;
        self.bPagesLoadedToGame = true;

        const w = self.PageSize.w;
        const h = self.PageSize.h;
        switch (self.Mode) {
            // mimick source font page layout
            .Source => {
                for (&self.Pages) |*p| {
                    // FIXME: doesn't this just load the same pixels to all 5
                    //  pages? why doesn't this get messed up, do we simply not
                    //  use it and therefore never caught it?
                    r3.hMaterial_OwnedNewFromData(pixeldata, w, h, w, h, .ARGB4444, &p.t, &p.m);
                }
                self.Fonts[0]._08_page_list[0] = &self.Pages[0].m;
                self.Fonts[0]._08_page_list[1] = &self.Pages[1].m;
                self.Fonts[0]._08_page_list[2] = &self.Pages[2].m;
                self.Fonts[1]._08_page_list[0] = &self.Pages[2].m;
                self.Fonts[2]._08_page_list[0] = &self.Pages[2].m;
                self.Fonts[3]._08_page_list[0] = &self.Pages[3].m;
                self.Fonts[4]._08_page_list[0] = &self.Pages[4].m;
            },
            // custom fonts only use one page
            .Custom => {
                const p = &self.Pages[0];
                r3.hMaterial_OwnedNewFromData(pixeldata, w, h, w, h, .ARGB4444, &p.t, &p.m);
                self.Fonts[0]._08_page_list[0] = &p.m;
                self.Fonts[1]._08_page_list[0] = &p.m;
                self.Fonts[2]._08_page_list[0] = &p.m;
                self.Fonts[3]._08_page_list[0] = &p.m;
                self.Fonts[4]._08_page_list[0] = &p.m;
            },
        }
    }

    pub fn UnloadPagesFromGame(self: *CustomFont) void {
        if (!self.bPagesLoadedToGame) return;
        self.bPagesLoadedToGame = false;

        switch (self.Mode) {
            .Source => for (&self.Pages) |*p| r3.hMaterial_OwnedFree(&p.m),
            .Custom => r3.hMaterial_OwnedFree(&self.Pages[0].m),
        }
    }

    // GlyphBin format (version 1):
    //      0x00    u32(LE)             binary version
    //      0x04    [5]CustomGlyphs     serialized data (version 1); variable size entries

    // TODO: convert `writer` to actual writer type after upgrading zig version
    pub fn GlyphBinSerialize(self: *const CustomFont, writer: anytype) !void {
        try writer.writeIntLittle(u32, GLYPH_BIN_VERSION);

        for (&self.Glyphs) |*glyphs| try glyphs.Serialize(writer);
    }

    // TODO: convert `reader` to actual reader type after upgrading zig version
    pub fn GlyphBinDeserialize(self: *CustomFont, reader: anytype) !void {
        const ver = try reader.readIntLittle(u32);
        if (ver != GLYPH_BIN_VERSION) return GlyphBinDeserializationError.VersionMismatch;

        for (&self.Glyphs) |*g| try g.Deserialize(reader);
    }

    // FIXME: crashes/errors if directory doesn't exist
    /// generates file containing the glyph definition data in binary form, used
    /// to "bake" adjusted glyphs for direct loading via @embedFile or similar
    pub fn GlyphBinDump(self: *const CustomFont, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();
        var file_bw = std.io.bufferedWriter(file.writer());
        defer _ = file_bw.flush() catch {};

        try self.GlyphBinSerialize(file_bw.writer());
    }
};

// TODO: tests for de/serialization
const CustomGlyphs = struct {
    Std: [STD_LEN]rf.GLYPH,
    Ext: [EXT_LEN]rf.GLYPH,
    StdSize: u32,
    ExtSize: u32,

    const STD_LEN = 62;
    const EXT_LEN = 15;

    pub const BINARY_VERSION: u32 = 1;
    pub const DeserializationError = error{ VersionMismatch, DataSizeTooLarge, DataSizeMismatch };

    pub fn CloneGameLists(self: *CustomGlyphs, glyphs_std: []rf.GLYPH, glyphs_ext: []rf.GLYPH) void {
        assert(glyphs_std.len <= STD_LEN);
        assert(glyphs_ext.len <= EXT_LEN);
        @memcpy(self.Std[0..glyphs_std.len], glyphs_std);
        @memcpy(self.Ext[0..glyphs_ext.len], glyphs_ext);
        self.StdSize = glyphs_std.len;
        self.ExtSize = glyphs_ext.len;
    }

    // TODO: ?? use some kind of custom struct (de)serializer that ensures GLYPH
    //  is serialized as LE? in future with expanded font stuff may be relevant
    //  for external tools
    // serialization format (version 1):
    // all fields LE; for now, rf.GLYPH fields implicitly so
    //     0x00    u32         version
    //     0x04    u32         StdSize
    //     0x08    u32         ExtSize
    //     0x0C    [?]rf.GLYPH Std[0..StdSize]
    //     0x??    [?]rf.GLYPH Ext[0..ExtSize]

    // TODO: convert `writer` to actual writer type after upgrading zig version
    pub fn Serialize(self: *const CustomGlyphs, writer: anytype) !void {
        try writer.writeIntLittle(u32, BINARY_VERSION);
        try writer.writeIntLittle(u32, self.StdSize);
        try writer.writeIntLittle(u32, self.ExtSize);
        _ = try writer.write(std.mem.sliceAsBytes(self.Std[0..self.StdSize]));
        _ = try writer.write(std.mem.sliceAsBytes(self.Ext[0..self.ExtSize]));
    }

    // TODO: convert `reader` to actual reader type after upgrading zig version
    pub fn Deserialize(self: *CustomGlyphs, reader: anytype) !void {
        const ver = try reader.readIntLittle(u32);
        if (ver != BINARY_VERSION) return DeserializationError.VersionMismatch;

        const std_size = try reader.readIntLittle(u32);
        if (std_size > STD_LEN) return DeserializationError.DataSizeTooLarge;
        self.StdSize = std_size;
        const ext_size = try reader.readIntLittle(u32);
        if (ext_size > EXT_LEN) return DeserializationError.DataSizeTooLarge;
        self.ExtSize = ext_size;

        const std_read = try reader.read(std.mem.sliceAsBytes(self.Std[0..std_size]));
        if (std_read != @sizeOf(rf.GLYPH) * std_size) return DeserializationError.DataSizeMismatch;
        const ext_read = try reader.read(std.mem.sliceAsBytes(self.Ext[0..ext_size]));
        if (ext_read != @sizeOf(rf.GLYPH) * ext_size) return DeserializationError.DataSizeMismatch;
    }
};

const CustomPage = struct {
    m: r3.Material = undefined,
    t: r3.SystemTexture = undefined,
};

// TODO: memory-efficient GIF/LZW implementation -> small buffer
// enough for max size custom font pixels (~12MB*2+6MB) plus some extra for
// scratch space. this amount could be brought down a lot, and potentially just
// be on the heap, if: 1) gif decoder is a streaming implementation that doesn't
// require the whole pixel buffer upfront, 2) LZW decoder within GIF uses a fixed
// buffer for the table hashmap, rather than being unbounded and potentially
// needing a similar amount of memory as the pixel buffer.
var load_scratch: [48 * 1024 * 1024]u8 = undefined;

// TODO: maintain hashmap of loaded custom font data as a cache, and refer to it
//  when attempting to load a font, to mitigate constantly loading the same font
//  into a new texture if the user messes with settings
// TODO: see how much of font init can be comptime. main issue it's not is that
//  initializing during comptime seems to give invalid internally-facing pointers
// TODO: precalculate glyph values and don't run adjustments at runtime in
//  release builds (or, only run adjustments via a setting/button)
// consolidated version of FontsInit and FontsLoad, for the purpose of streamlining
fn FontsLoad() void {
    if (fonts_loaded) return;
    fonts_loaded = true;

    // TODO: ?? move to plugin level, not custom font level? (for the sake of
    //  cleanly separating them for toggle-ability, even though it only really
    //  affects custom fonts)
    PatchTextClippingBug(true);

    var fba = std.heap.FixedBufferAllocator.init(&load_scratch);
    var arena = std.heap.ArenaAllocator.init(fba.allocator());
    const alloc = arena.allocator();

    // FIXME: error handling for the whole block; fallback to disabled font features,
    //  adjustments for custom fonts cannot be made if this fails (if not loading baked)
    FixedFontFromStock(alloc, &font_stock_fixed) catch |e|
        PPanic("(FontsLoad) stock to fixed: {s}", .{@errorName(e)});
    _ = arena.reset(.retain_capacity);

    // NOTE: embedded gif should not fail, if this crashes it is programmer error
    var stock_custom_fbs = std.io.fixedBufferStream(@embedFile("embed/font_stock.gif"));
    CustomFontFromFixed(alloc, &font_stock_custom, "stock fixed", stock_custom_fbs.reader()) catch unreachable;
    _ = arena.reset(.retain_capacity);

    // TODO: when getting around to remaking the hd font with better proportions,
    //  rename this to "hd-classic" to preserve the old font and use "hd" for the
    //  new version (so that users are auto-updated to the new version, but still
    //  have the old version available)
    // FIXME: error handling for the whole block; fallback to fixed stock
    const path_hd = GIFCustomFontPath(alloc, "hd") catch unreachable;
    CustomFontFromFixedFile(alloc, &font_custom, path_hd) catch |e|
        PPanic("(FontsLoad) hd: {s}", .{@errorName(e)});
    _ = arena.reset(.retain_capacity);
}

fn FontsUnload() void {
    if (!fonts_loaded) return;
    fonts_loaded = false;

    // TODO: ?? move to plugin level, not custom font level? (for the sake of
    //  cleanly separating them for toggle-ability, even though it only really
    //  affects custom fonts)
    PatchTextClippingBug(false);

    UpdateGameFont(null);
    font_stock_custom.UnloadPagesFromGame();
    // FIXME: in future, will need to unload whole hashmap cache of loaded fonts
    font_custom.UnloadPagesFromGame();
}

const CUSTOM_FONT_W = 256;
const CUSTOM_FONT_H = 192;
const CUSTOM_FONT_MAX_SCALE = 8;
const CUSTOM_FONT_USE_GLYPH_BINARY = true; // FIXME: set to `true` for release/when not testing

fn FixedFontFromStock(arena: Allocator, font: *CustomFont) !void {
    var glyphs = try arena.alloc(CustomGlyphs, 5);

    glyphs[0].CloneGameLists(rf.aFontGlyphs0, rf.aFontGlyphs0Ext);
    glyphs[1].CloneGameLists(rf.aFontGlyphs1, &.{});
    glyphs[2].CloneGameLists(rf.aFontGlyphs2, &.{});
    glyphs[3].CloneGameLists(rf.aFontGlyphs3, rf.aFontGlyphs3Ext);
    glyphs[4].CloneGameLists(rf.aFontGlyphs4, rf.aFontGlyphs4Ext);

    font.Init(.Source, 64, 128, "Stock Fixed Base");
    font.CloneFonts(rf.aFontDef, true);
    if (CUSTOM_FONT_USE_GLYPH_BINARY) {
        font.GlyphsFromBin(@embedFile("embed/font_glyphs_fixed.bin"));
    } else {
        font.GlyphsFromAdjustment(@ptrCast(glyphs), &GLYPH_ADJUSTMENT_STOCK_TO_FIXED);
    }
}

const ReadCustomFontError = error{
    FileExtensionInvalid,
    FileOpenError,
    NameTooLong,
    NameNotAscii, // "printable" characters from codes 32 to 126
    DimensionsInvalid,
    DataReadError,
};

// TODO: convert `reader` to actual reader type after upgrading zig version
// NOTE: user-facing "fixed" font is a custom font made here, using the pure stock fixed base
// "fixed" meaning, the stock font with standard adjustments
fn CustomFontFromFixed(arena: Allocator, font: *CustomFont, name: []const u8, reader: anytype) ReadCustomFontError!void {
    assert(name.len <= 127);

    // TODO: is the zero-init necessary?
    var gif = std.mem.zeroes(GIF);
    gif.ReadHead(arena, reader) catch return ReadCustomFontError.DataReadError;

    const w = gif.CanvasW;
    const h = gif.CanvasH;

    if (!(w / CUSTOM_FONT_W == h / CUSTOM_FONT_H) or
        !(w / CUSTOM_FONT_W <= CUSTOM_FONT_MAX_SCALE) or
        !(w / CUSTOM_FONT_W >= 1) or
        !(w % CUSTOM_FONT_W == 0) or
        !(h % CUSTOM_FONT_H == 0))
        return ReadCustomFontError.DimensionsInvalid;

    font.Init(.Custom, w, h, name);

    // TODO: make not based on stock font, once custom font capabilities expanded;
    //  some stale data is present, such as wrong page counts, potentially invalid
    //  character ranges, etc.
    font.CloneFonts(rf.aFontDef, false);

    // FIXME: remove hardcoded font_fixed_stock ref?
    if (CUSTOM_FONT_USE_GLYPH_BINARY) {
        font.GlyphsFromBin(@embedFile("embed/font_glyphs_custom.bin"));
    } else {
        font.GlyphsFromAdjustment(&font_stock_fixed.Glyphs, &GLYPH_ADJUSTMENT_FIXED_TO_CUSTOM);
    }

    var pagebuf = arena.alloc(u16, @as(u32, w) * h) catch return ReadCustomFontError.DataReadError;
    GIFBodyToAlphaARGB4444(&gif, arena, reader, pagebuf) catch return ReadCustomFontError.DataReadError;
    font.LoadPagesToGame(pagebuf);
}

fn CustomFontFromFixedFile(arena: Allocator, font: *CustomFont, filepath: []const u8) ReadCustomFontError!void {
    assert(filepath.len >= 4); // at least as long as an accepted file extension

    var filename_ext: [4]u8 = undefined;
    _ = std.ascii.lowerString(&filename_ext, filepath[filepath.len - 4 .. filepath.len]);
    if (!std.mem.eql(u8, ".gif", &filename_ext)) return ReadCustomFontError.FileExtensionInvalid;

    const filename = blk: {
        var it = std.mem.splitBackwardsScalar(u8, filepath, '/');
        break :blk it.first();
    };
    const name = filename[0 .. filename.len - 4];
    if (name.len > 127) return ReadCustomFontError.NameTooLong;
    const range = std.mem.minMax(u8, name);
    if (range.min < 32 or range.max > 126) return ReadCustomFontError.NameNotAscii; // unprintable characters

    const file = std.fs.cwd().openFile(filepath, .{}) catch return ReadCustomFontError.FileOpenError;
    defer file.close();
    var file_br = std.io.bufferedReader(file.reader());

    try CustomFontFromFixed(arena, font, name, file_br.reader());
}

fn UpdateGameFont(font: ?*const CustomFont) void {
    const table: u32 = if (font) |f| @intFromPtr(&f.FontTable) else @intFromPtr(rt.apTextFont);

    // regardless of font texture scale, the same values are used because the UVs
    // are calculated based on the glyph values, not from the real texture dimensions
    const unit_scale_x: f32 = 1 / @as(f32, if (font) |_| CUSTOM_FONT_W else 64);
    const unit_scale_y: f32 = 1 / @as(f32, if (font) |_| CUSTOM_FONT_H else 128);

    // font table reference
    _ = mem.write(0x42D8EE + 3, u32, table);

    // font atlas unit scale for converting texture coordinates to UVs
    // because all glyphs use these values regardless of font def, all font pages
    // of a font must be the same size; if not, this value would need to be updated
    // every time a font is selected from the font table
    _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleX), f32, unit_scale_x);
    _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleY), f32, unit_scale_y);
}
