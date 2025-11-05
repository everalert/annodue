const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

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

// FIXME: remove, for testing
const dbg = @import("util/debug.zig");
const rd = @import("racer").Debug;

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
//            fonts; the problem may be that some text is cut off at the screen
//            extents due to the way racer "fixes" UVs on sprite overdraw, which
//            could cause some cutoff with margins when it otherwise wouldn't
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

// TODO: all settings hot-reloadable
// TODO: embed fonts and point to ours, rather than patching the whole thing (for faster loadtimes)
// TODO: dump fonts as a button on a menu, not a weirdge on-launch only thing
// TODO: option to show double-size fonts on font test visualization
// NOTE: consider halving old hd font, as this would enable the max texture size
// of custom fonts to be 4x less. in this case, glyphs will still be oversized for
// normal text, but undersized for "large" text (~75% @ 1440p, ~85-90% @ 1080p).
// possibly acceptable (unscaled non-large normal body text @ 960p has similar
// ratio and is subjectively good-looking), but ~6x base size would be needed for
// no/minimal scaling in all cases; 8x is actually justified for pow2.

// FIXME: re-dump original font data to tga, and remake the base template font;
// ExtractRawFontPagesToGrey8 was implemented incorrectly and generates the wrong
// color values, and these images were used to make the current font. any images
// made through these functions should be re-generated
// fontsheet to remake: (basic-original.gif)
// other things to update
// - do final check on it for random white pixels that are meant to be bg
// - swap order of superscript a and o in body fonts to match title font, and
//   update the font adjustment defs accordingly
// - make sure apostrophes on body fonts use comma glyph (check against updated
//   template, not old output sheet)
// FIXME: update changelog and manual to reflect new font functionality and stuff
// inherited from cosmetic/developer plugins, as well as updating old parts of
// current changelog that talk about font-related features on other plugins in
// this release round

// FEATURES
// - High-resolution fonts
// - Dump font data to file on launch (font sheets and glyph templates)
// - SETTINGS:
//   patch_fonts            bool    * requires game restart to apply
//   dump_fonts             bool    * requires game restart to apply

const PLUGIN_NAME: [*:0]const u8 = "Font";
const PLUGIN_VERSION: [*:0]const u8 = "0.0.1";

const FontState = struct {
    var h_s_section: ?SettingHandle = null;
    var h_s_patch_fonts: ?SettingHandle = null;
    var h_s_dump_fonts: ?SettingHandle = null;
    var s_patch_fonts: bool = false;
    var s_dump_fonts: bool = false;
    var dump_fonts_done: bool = false;

    fn settingsInit(gf: *GlobalFn) void {
        const section = gf.ASettingSectionOccupy(SettingHandle.getNull(), "font", null);
        h_s_section = section;

        h_s_patch_fonts =
            gf.ASettingOccupy(section, "patch_fonts", .B, .{ .b = false }, &s_patch_fonts, null);
        h_s_dump_fonts = // working?
            gf.ASettingOccupy(section, "dump_fonts", .B, .{ .b = false }, &s_dump_fonts, null);
    }

    // FIXME: crashes, but only in OnInit; not on arbitrary keypress in the other
    // version, nor here on plugin hot-reload (i.e. OnInitLate)
    // TODO: make sure it only dumps once, even when hot reloading; alternatively,
    // make it dump with a button press in a menu
    fn settingsFontDump(value: Setting.Value) callconv(.C) void {
        if (value.b and !dump_fonts_done)
            FontDump();
    }

    fn FontDump() void {
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
        DrawFontGlyphRegions(&font[0], &font[1], &font[2], rf.aFontGlyphs0, rf.aFontGlyphs0Ext, 64, 128);
        DrawFontGlyphRegions(&font[2], null, null, rf.aFontGlyphs1, null, 64, 128);
        DrawFontGlyphRegions(&font[2], null, null, rf.aFontGlyphs2, null, 64, 128);
        DrawFontGlyphRegions(&font[3], null, null, rf.aFontGlyphs3, rf.aFontGlyphs3Ext, 64, 128);
        DrawFontGlyphRegions(&font[4], null, null, rf.aFontGlyphs4, rf.aFontGlyphs4Ext, 64, 128);
        DumpGrey8toTGA(&font[0], 64, 128, "annodue/developer/fontraw0_mask.tga");
        DumpGrey8toTGA(&font[1], 64, 128, "annodue/developer/fontraw1_mask.tga");
        DumpGrey8toTGA(&font[2], 64, 128, "annodue/developer/fontraw2_mask.tga");
        DumpGrey8toTGA(&font[3], 64, 128, "annodue/developer/fontraw3_mask.tga");
        DumpGrey8toTGA(&font[4], 64, 128, "annodue/developer/fontraw4_mask.tga");

        DumpFontDefToCSV(&rf.aFontDef[0], 61, 15, "annodue/developer/fontdata0");
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

fn ExtractRawFontPagesToGrey8(buf: *[5][0x2000]u8) void {
    for (buf, 0..) |*b, i| {
        const page = &rf.aFontRawPageData[i];
        for (page, 0..) |px, j| {
            const px_i = j * 2;
            // FIXME: this maps to the wrong grey shade; e.g. full white becomes 240
            b[px_i + 0] = @as(u8, @intCast(ra.hExtract4BPP(px, 0))) << 4;
            b[px_i + 1] = @as(u8, @intCast(ra.hExtract4BPP(px, 1))) << 4;
        }
    }
}

fn DrawFontGlyphRegions(
    p1: ?[]u8,
    p2: ?[]u8,
    p3: ?[]u8,
    gs1: ?[]const rf.GLYPH,
    gs2: ?[]const rf.GLYPH,
    page_w: i16,
    page_h: i16,
) void {
    const pages = &[_]?[]u8{ p1, p2, p3 };
    const glyph_sets = &[_]?[]const rf.GLYPH{ gs1, gs2 };
    for (glyph_sets) |gs| {
        if (gs == null) continue;
        for (gs.?) |*g| {
            if (g.TexX == -1) continue; // not implemented in font data
            assert(pages[@intCast(g.PageID)] != null);
            assert(pages[@intCast(g.PageID)].?.len == page_w * page_h);
            const page = pages[@intCast(g.PageID)].?;
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
    assert(pixels.len == width * height);
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

// NOTE: the original patcher referred to this as a 'texture' table, but this is
// actually a vtable pointing to 'sprite'-type pages; this is the same basic format
// as other sprites, but all of the header data is stripped in the case of the
// embedded font data, in lieu of hardcoded assumptions about format, dimensions, etc.
// WARNING: the original dumped font data (see dll_developer) has some offset pixels
// and wrapping, but the hd fonts don't; not sure if this is handled by this function
// or if the dumper is just dumping wrong
// WARNING: also don't really know how the '.data' files this function takes were
// generated from the png files
// ---- comments from when originally porting below ----
// NOTE: code_begin_offset = part of the arguments to a function call (sprite
// setup-related fn fn_445EE0); args expected in this range: maxwidth?, maxheight?,
// width, height (args 3-6)
// NOTE: code_end_offset = the instruction after 4 arguments later
// NOTE: texture table seems to be 'len' in first field (u32), followed by len ptrs
// to texture segments
// FIXME: can probably convert font->sprite conversion to comptime embed then hook
// up ptrs only in code, then all the allocation bs can be skipped
// NOTE: probably cannot reverse this, because it patches something that seems to
// only run once during setup
fn PatchTextureTable(
    memory: usize,
    table_offset: usize,
    code_begin_offset: usize,
    code_end_offset: usize,
    width: u32,
    height: u32,
    filename: []const u8,
) usize {
    var off: usize = memory;
    off = x86.nop_align(off, 16);

    // Original code takes u8 dimension args, so we use our own code that takes u32
    const cave_memory_offset: usize = off;

    // Patches the arguments for the texture loader
    off = x86.push(off, .{ .imm32 = height });
    off = x86.push(off, .{ .imm32 = width });
    off = x86.push(off, .{ .imm32 = height });
    off = x86.push(off, .{ .imm32 = width });
    off = x86.jmp(off, code_end_offset);

    // Detour original code to ours
    var hack_offset: usize = x86.jmp(code_begin_offset, cave_memory_offset);
    _ = x86.nop_until(hack_offset, code_end_offset);

    const page_num: u32 = mem.read(table_offset + 0, u32);

    for (0..page_num) |i| {
        _ = mem.write(table_offset + 4 + i * 4, u32, off); // update table entry ptr
        off = LoadSpritePage(off, width, height, filename, i);
    }

    return off;
}

// loads some GIMP format into Greyscale4 format (0x400) in preparation for game
// parsing as sprite data
fn LoadSpritePage(
    write_at: u32,
    width: u32,
    height: u32,
    filename: []const u8,
    page: u32,
) u32 {
    var off = write_at;

    const page_size: u32 = width * height * 4 / 8;

    // Loop over all pages
    var str_buf: [1023:0]u8 = undefined;
    const buffer_slice = @as([*]u8, @ptrFromInt(off))[0..page_size];
    @memset(buffer_slice, 0x00);

    // Load input texture to buffer
    var path = std.fmt.bufPrintZ(&str_buf, "annodue/textures/{s}_{d}_test.data", .{ filename, page }) catch
        @panic("LoadSpritePage: formatting texture file path"); // FIXME: error handling

    const file = std.fs.cwd().openFile(path, .{}) catch
        @panic("LoadSpritePage: opening texture file"); // FIXME: error handling
    defer file.close();
    var br = std.io.bufferedReader(file.reader());
    const r = br.reader();
    for (0..page_size * 2) |j| {
        const px = r.readInt(u16, .Little) catch @panic("LoadSpritePage: pixel read"); // FIXME: error handling
        buffer_slice[j / 2] |= ra.hInsert4BPP(ra.hGA88toG4(px), j);
    }

    off += page_size;
    off = x86.nop_align(off, 0x10);
    return off;
}

// dumps precomputed RGBA4444 data into buffer
fn LoadPreComputedSpritePage(
    buf_o: []u16,
    width: u32,
    height: u32,
    filename: []const u8,
) void {
    assert(buf_o.len == width * height);
    var str_buf: [1023:0]u8 = undefined;

    const px_num: u32 = width * height;
    @memset(buf_o, 0x00);

    // FIXME: error handling
    var path = std.fmt.bufPrintZ(&str_buf, "annodue/textures/{s}.data", .{filename}) catch |e|
        PPanic("(LoadPreComputedSpritePage) formatting file path: {e}", .{@errorName(e)});

    // FIXME: error handling
    const file = std.fs.cwd().openFile(path, .{}) catch |e|
        PPanic("(LoadPreComputedSpritePage) opening file: {s}", .{@errorName(e)});
    defer file.close();
    var br = std.io.bufferedReader(file.reader());
    const r = br.reader();
    for (0..px_num) |i| {
        // FIXME: error handling
        buf_o[i] = r.readInt(u16, .Little) catch |e|
            PPanic("(LoadPreComputedSpritePage) pixel read: {s}", .{@errorName(e)});
    }
}

// ------------
// glyph adjustment
// ------------

const GlyphFieldAdjustment = struct {
    const T = enum { Set, Add };
    const F = enum { Pg, Ad, OX, OY, TX, TY, TW, TH };
    t: T,
    f: F,
    v: i16,
};

const GlyphAdjustment = struct {
    i: usize,
    a: GlyphFieldAdjustment,
};

fn CloneAndAdjustGlyphSet(src: []const rf.GLYPH, dst: []rf.GLYPH, adjustments: []const GlyphAdjustment) void {
    assert(src.len == dst.len);
    @memcpy(dst, src);
    AdjustGlyphSet(dst, adjustments);
}

fn AdjustGlyphSet(set: []rf.GLYPH, adjustments: []const GlyphAdjustment) void {
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

inline fn GFA(
    t: GlyphFieldAdjustment.T,
    f: GlyphFieldAdjustment.F,
    v: i16,
) GlyphFieldAdjustment {
    return .{ .t = t, .f = f, .v = v };
}

// ------------
// Custom stuff workspace
// ------------

// NOTE: scratchpad notes
//
// - will need to adjust :;-+ dims on title font beyond just margin
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

// FIXME: to organize/streamline; random stuff used to work through feature dev
var fonts_initialized = false;
const custom_fonts = [_]struct { *const [7]*rf.FONT, []const u8, f32, f32 }{
    .{ &font_table_new, "base font (fixed, new atlas)", 256, 256 },
    .{ &font_table_adj, "base font (fixed)", 64, 128 },
    //.{ &font_table, "HD font", 64, 128 },
};
var fonts_using: bool = false;
var custom_font_active: u32 = 0;
var font_page_unit_scale_x: f32 = 1 / 64;
var font_page_unit_scale_y: f32 = 1 / 128;

const FontPage = struct {
    r: []u16,
    m: r3.Material = undefined,
    t: r3.SystemTexture = undefined,
};

const font_table = [7]*rf.FONT{
    &fonts[3], &fonts[2], &fonts[1], &fonts[2],
    &fonts[4], &fonts[3], &fonts[0],
};
var fonts: [5]rf.FONT = undefined;
var fonts_loaded: bool = false;
var dp: ?*i32 = null;
var fpage_raw = std.mem.zeroes([5][512 * 1024]u16);
var fpage = pages: {
    var p: [5]FontPage = undefined;
    assert(fpage_raw.len == 5);
    assert(p.len >= 5);

    for (0..p.len) |i|
        p[i].r = &fpage_raw[i % 5];

    break :pages p;
};

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

var fpage_new_raw = std.mem.zeroes([256 * 256]u16); // TODO: resize for max size custom font
var fpage_new = FontPage{ .r = &fpage_new_raw };

const font_table_new = [7]*rf.FONT{
    &fonts_new[3], &fonts_new[2], &fonts_new[1], &fonts_new[2],
    &fonts_new[4], &fonts_new[3], &fonts_new[0],
};
var fonts_new: [5]rf.FONT = undefined;
var fonts_new_f0g: [61]rf.GLYPH = undefined;
var fonts_new_f0ge: [15]rf.GLYPH = undefined;
var fonts_new_f1g: [27]rf.GLYPH = undefined;
var fonts_new_f2g: [27]rf.GLYPH = undefined;
var fonts_new_f3g: [62]rf.GLYPH = undefined;
var fonts_new_f3ge: [15]rf.GLYPH = undefined;
var fonts_new_f4g: [62]rf.GLYPH = undefined;
var fonts_new_f4ge: [15]rf.GLYPH = undefined;

const font_table_adj = [7]*rf.FONT{
    &fonts_adj[3], &fonts_adj[2], &fonts_adj[1], &fonts_adj[2],
    &fonts_adj[4], &fonts_adj[3], &fonts_adj[0],
};
var fonts_adj: [5]rf.FONT = undefined;
var fonts_adj_f0g: [61]rf.GLYPH = undefined;
var fonts_adj_f0ge: [15]rf.GLYPH = undefined;
var fonts_adj_f1g: [27]rf.GLYPH = undefined;
var fonts_adj_f2g: [27]rf.GLYPH = undefined;
var fonts_adj_f3g: [62]rf.GLYPH = undefined;
var fonts_adj_f3ge: [15]rf.GLYPH = undefined;
var fonts_adj_f4g: [62]rf.GLYPH = undefined;
var fonts_adj_f4ge: [15]rf.GLYPH = undefined;

// FIXME: add as an actual plugin feature with a settings toggle
const gfa_disable = GFA(.Set, .TX, -1);
const font0_g_adj = [_]GlyphAdjustment{
    .{ .i = 1, .a = gfa_disable },
    .{ .i = 2, .a = GFA(.Add, .OX, 5) },
    .{ .i = 3, .a = gfa_disable },
    .{ .i = 4, .a = gfa_disable },
    .{ .i = 7, .a = GFA(.Add, .OX, 5) },
    .{ .i = 8, .a = gfa_disable },
    .{ .i = 9, .a = gfa_disable },
    .{ .i = 10, .a = gfa_disable },
    .{ .i = 11, .a = GFA(.Add, .Ad, 3) },
    .{ .i = 12, .a = gfa_disable },
    .{ .i = 14, .a = gfa_disable },
    .{ .i = 12, .a = GFA(.Add, .Ad, 3) },
    .{ .i = 14, .a = GFA(.Add, .Ad, 5) },
    .{ .i = 15, .a = GFA(.Add, .OY, -1) },
    .{ .i = 27, .a = gfa_disable },
    .{ .i = 27, .a = GFA(.Add, .Ad, 5) }, // TODO: tweak against real text (use fixed new atlas)
    .{ .i = 28, .a = gfa_disable },
    .{ .i = 30, .a = gfa_disable },
    .{ .i = 35, .a = GFA(.Add, .OX, -1) },
    .{ .i = 51, .a = GFA(.Add, .OX, -1) },
    .{ .i = 57, .a = GFA(.Add, .OX, -1) },
};
const font0_ge_adj = [_]GlyphAdjustment{
    .{ .i = 1, .a = gfa_disable },
    .{ .i = 2, .a = gfa_disable },
    .{ .i = 6, .a = GFA(.Add, .OX, 1) },
    .{ .i = 7, .a = GFA(.Add, .OX, 1) },
    .{ .i = 8, .a = GFA(.Add, .OX, 1) },
    .{ .i = 9, .a = GFA(.Add, .OX, 2) },
    .{ .i = 10, .a = GFA(.Add, .OX, 1) },
    .{ .i = 11, .a = GFA(.Add, .OX, 2) },
    .{ .i = 13, .a = GFA(.Add, .OY, -2) },
    .{ .i = 14, .a = GFA(.Add, .OY, -2) },
};
const font1_g_adj = [_]GlyphAdjustment{
    .{ .i = 1, .a = gfa_disable },
    .{ .i = 3, .a = gfa_disable },
    .{ .i = 4, .a = gfa_disable },
    .{ .i = 7, .a = gfa_disable },
    .{ .i = 8, .a = gfa_disable },
    .{ .i = 9, .a = gfa_disable },
    .{ .i = 10, .a = gfa_disable },
    .{ .i = 12, .a = gfa_disable },
    .{ .i = 13, .a = gfa_disable },
    .{ .i = 14, .a = gfa_disable },
    .{ .i = 14, .a = GFA(.Add, .Ad, 5) },
    .{ .i = 15, .a = gfa_disable },
};
const font2_g_adj = [_]GlyphAdjustment{
    .{ .i = 1, .a = gfa_disable },
    .{ .i = 3, .a = gfa_disable },
    .{ .i = 4, .a = gfa_disable },
    .{ .i = 7, .a = gfa_disable },
    .{ .i = 8, .a = gfa_disable },
    .{ .i = 9, .a = gfa_disable },
    .{ .i = 10, .a = gfa_disable },
    .{ .i = 12, .a = gfa_disable },
    .{ .i = 13, .a = gfa_disable },
    .{ .i = 23, .a = GFA(.Add, .OX, -1) },
};
const font3_g_adj = [_]GlyphAdjustment{
    .{ .i = 3, .a = gfa_disable },
    .{ .i = 4, .a = gfa_disable },
    .{ .i = 8, .a = gfa_disable },
    .{ .i = 9, .a = gfa_disable },
    .{ .i = 11, .a = GFA(.Add, .TY, 1) },
    .{ .i = 12, .a = GFA(.Add, .OY, -2) },
    .{ .i = 13, .a = GFA(.Add, .OX, -1) },
    .{ .i = 17, .a = GFA(.Add, .OX, 1) },
    .{ .i = 17, .a = GFA(.Add, .TX, -1) },
    .{ .i = 26, .a = GFA(.Add, .OY, -1) },
    .{ .i = 28, .a = gfa_disable },
    .{ .i = 30, .a = gfa_disable },
};
const font3_ge_adj = [_]GlyphAdjustment{
    // pound (currency); this one may be intentional, overlaps 'L'
    //.{ .i = 2, .a = gfa_disable },
    .{ .i = 3, .a = GFA(.Set, .TX, 20) },
    .{ .i = 4, .a = GFA(.Set, .TX, 12) },
};
const font4_g_adj = [_]GlyphAdjustment{
    .{ .i = 2, .a = GFA(.Add, .OY, 1) },
    .{ .i = 2, .a = GFA(.Add, .TH, -2) },
    .{ .i = 7, .a = GFA(.Add, .OY, 1) },
    .{ .i = 7, .a = GFA(.Add, .TH, -2) },
    .{ .i = 10, .a = gfa_disable },
    .{ .i = 12, .a = GFA(.Add, .TH, -2) },
    .{ .i = 14, .a = GFA(.Set, .TX, 1) },
    .{ .i = 14, .a = GFA(.Set, .TY, 25) },
    .{ .i = 14, .a = GFA(.Set, .TW, 3) },
    .{ .i = 17, .a = GFA(.Add, .OX, -1) },
    .{ .i = 20, .a = GFA(.Add, .OX, -1) },
    .{ .i = 23, .a = GFA(.Add, .OX, 1) },
    .{ .i = 28, .a = gfa_disable },
    .{ .i = 30, .a = gfa_disable },
    .{ .i = 61, .a = GFA(.Add, .OX, 1) },
    .{ .i = 61, .a = GFA(.Add, .TX, -1) },
    .{ .i = 61, .a = GFA(.Add, .TW, 1) },
};
const font4_ge_adj = [_]GlyphAdjustment{
    .{ .i = 1, .a = GFA(.Set, .TX, 27) },
    .{ .i = 1, .a = GFA(.Set, .TY, 21) },
    .{ .i = 2, .a = gfa_disable },
    .{ .i = 3, .a = GFA(.Add, .OY, 1) },
    .{ .i = 4, .a = GFA(.Add, .OY, 1) },
    .{ .i = 9, .a = GFA(.Add, .OX, 2) },
    .{ .i = 11, .a = GFA(.Add, .OX, 1) },
    .{ .i = 13, .a = GFA(.Add, .OY, -1) },
    .{ .i = 14, .a = GFA(.Add, .OY, -1) },
};

///                   id     tx   ty   tw   th   ox   oy
const CGAP = struct { usize, i16, i16, i16, i16, i16, i16 };

inline fn CGA(
    comptime p: []const usize,
    comptime a: []const CGAP,
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

const font0_new_g_adj = CGA(&[_]usize{
    2,  7,  13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
    23, 24, 25, 26, 31, 52, 53, 54, 55, 56, 57, 58,
}, &[_]CGAP{
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

const font0_new_ge_adj = CGA(&[_]usize{
    0,  1,  2,  3, 4, 5, 6, 7, 8, 9, 10, 11,
    12, 13, 14,
}, &[_]CGAP{
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

const font1_new_g_adj = CGA(&[_]usize{}, &[_]CGAP{
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

const font2_new_g_adj = CGA(&[_]usize{}, &[_]CGAP{
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

const font3_new_g_adj = CGA(&[_]usize{}, &[_]CGAP{
    .{ 2, 65, 149, 9, 8, 2, 2 }, // " // FIXME: adjust offset after fixing atlas
    .{ 7, 74, 149, 9, 8, 2, 2 }, // ' // FIXME: adjust offset after fixing atlas
    .{ 10, 226, 133, 13, 15, 2, 2 }, // +
    .{ 11, 241, 133, 15, 15, 2, 2 }, // *
    .{ 13, 97, 143, 7, 9, 1, 4 }, // - // FIXME: adjust offset after fixing atlas
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

const font3_new_ge_adj = CGA(&[_]usize{}, &[_]CGAP{
    .{ 1, 111, 143, 7, 11, 2, 2 }, // inverted !
    .{ 2, 144, 144, 10, 11, 2, 2 }, // pound (currency)
    .{ 3, 166, 144, 12, 11, 2, 2 }, // superscript a
    .{ 4, 154, 144, 11, 11, 2, 2 }, // superscript o
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

const font4_new_g_adj = CGA(&[_]usize{}, &[_]CGAP{
    .{ 2, 74, 180, 9, 7, 2, 2 }, // " // FIXME: adjust offset after fixing atlas
    .{ 7, 83, 180, 9, 7, 2, 2 }, // ' // FIXME: adjust offset after fixing atlas
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

const font4_new_ge_adj = CGA(&[_]usize{}, &[_]CGAP{
    .{ 1, 120, 179, 7, 11, 3, 3 }, // inverted !
    .{ 3, 189, 179, 12, 11, 2, 2 }, // superscript a
    .{ 4, 177, 179, 12, 11, 2, 2 }, // superscript o
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

fn FontsInit() void {
    if (fonts_initialized) return;
    AdjustmentFontsInit();
    CustomFontsInit();
    fonts_initialized = true;
}

fn FontsLoad() void {
    if (fonts_loaded) return;
    AdjustmentFontsLoad();
    CustomFontsLoad();
    fonts_loaded = true;
}

fn FontsUnload() void {
    if (!fonts_loaded) return;
    AdjustmentFontsUnload();
    CustomFontsUnload();
    _ = mem.write(0x42D8EE + 3, u32, @intFromPtr(rt.apTextFont));
    _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleX), f32, 1 / 64);
    _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleY), f32, 1 / 128);
    fonts_loaded = false;
}

// WARN: do not use directly; use FontsInit
fn AdjustmentFontsInit() void {
    if (fonts_initialized) return;

    @memcpy(&fonts_adj, rf.aFontDef);
    fonts_adj[0]._5C_glyphs = &fonts_adj_f0g;
    fonts_adj[0]._60_glyphs_ext = &fonts_adj_f0ge;
    fonts_adj[1]._5C_glyphs = &fonts_adj_f1g;
    fonts_adj[2]._5C_glyphs = &fonts_adj_f2g;
    fonts_adj[3]._5C_glyphs = &fonts_adj_f3g;
    fonts_adj[3]._60_glyphs_ext = &fonts_adj_f3ge;
    fonts_adj[4]._5C_glyphs = &fonts_adj_f4g;
    fonts_adj[4]._60_glyphs_ext = &fonts_adj_f4ge;

    CloneAndAdjustGlyphSet(rf.aFontGlyphs0, &fonts_adj_f0g, &font0_g_adj);
    CloneAndAdjustGlyphSet(rf.aFontGlyphs0Ext, &fonts_adj_f0ge, &font0_ge_adj);
    CloneAndAdjustGlyphSet(rf.aFontGlyphs1, &fonts_adj_f1g, &font1_g_adj);
    CloneAndAdjustGlyphSet(rf.aFontGlyphs2, &fonts_adj_f2g, &font2_g_adj);
    CloneAndAdjustGlyphSet(rf.aFontGlyphs3, &fonts_adj_f3g, &font3_g_adj);
    CloneAndAdjustGlyphSet(rf.aFontGlyphs3Ext, &fonts_adj_f3ge, &font3_ge_adj);
    CloneAndAdjustGlyphSet(rf.aFontGlyphs4, &fonts_adj_f4g, &font4_g_adj);
    CloneAndAdjustGlyphSet(rf.aFontGlyphs4Ext, &fonts_adj_f4ge, &font4_ge_adj);
}

// WARN: do not use directly; use FontsLoad
fn AdjustmentFontsLoad() void {
    if (fonts_loaded) return;
}

// WARN: do not use directly; use FontsUnload
fn AdjustmentFontsUnload() void {
    if (!fonts_loaded) return;
}

// FIXME: relocate, for testing
const gif = @import("util/gif.zig");
const cf = @import("util/color_format.zig");

// FIXME: this and CustomFontsLoad seems to cause noticeable lag at title screen
// on game load now, must fix this before moving on
// WARN: do not use directly; use FontsInit
fn CustomFontsInit() void {
    if (fonts_initialized) return;

    // old hd font

    @memcpy(&fonts, rf.aFontDef);
    var filename = [_]u8{ 'f', 'o', 'n', 't', 'r', 'a', 'w', '0', '_', 't', 'e', 's', 't' };
    for (0..5) |i| {
        filename[7] = '0' + @as(u8, @truncate(i));
        LoadPreComputedSpritePage(fpage[i].r, 512, 1024, &filename);
    }

    // new custom font framework proof of concept

    @memcpy(&fonts_new, rf.aFontDef);
    fonts_new[0]._5C_glyphs = &fonts_new_f0g;
    fonts_new[0]._60_glyphs_ext = &fonts_new_f0ge;
    fonts_new[1]._5C_glyphs = &fonts_new_f1g;
    fonts_new[2]._5C_glyphs = &fonts_new_f2g;
    fonts_new[3]._5C_glyphs = &fonts_new_f3g;
    fonts_new[3]._60_glyphs_ext = &fonts_new_f3ge;
    fonts_new[4]._5C_glyphs = &fonts_new_f4g;
    fonts_new[4]._60_glyphs_ext = &fonts_new_f4ge;
    // FIXME: just using standard adjustment for now to get things running; need
    // to clone the pre-adjusted glyphs and further adjust for new atlas
    CloneAndAdjustGlyphSet(&fonts_adj_f0g, &fonts_new_f0g, &font0_new_g_adj);
    CloneAndAdjustGlyphSet(&fonts_adj_f0ge, &fonts_new_f0ge, &font0_new_ge_adj);
    CloneAndAdjustGlyphSet(&fonts_adj_f1g, &fonts_new_f1g, &font1_new_g_adj);
    CloneAndAdjustGlyphSet(&fonts_adj_f2g, &fonts_new_f2g, &font2_new_g_adj);
    CloneAndAdjustGlyphSet(&fonts_adj_f3g, &fonts_new_f3g, &font3_new_g_adj);
    CloneAndAdjustGlyphSet(&fonts_adj_f3ge, &fonts_new_f3ge, &font3_new_ge_adj);
    CloneAndAdjustGlyphSet(&fonts_adj_f4g, &fonts_new_f4g, &font4_new_g_adj);
    CloneAndAdjustGlyphSet(&fonts_adj_f4ge, &fonts_new_f4ge, &font4_new_ge_adj);

    // FIXME: rethink where the allocator comes from
    // FIXME: also, need to handle cases where the gif is the wrong size; can cause
    // buffer overflow etc.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // FIXME: error handling
    const file = std.fs.cwd().openFile("annodue/textures/font-basic-original.gif", .{}) catch |e|
        PPanic("(CustomFontsInit) opening gif: {s}", .{@errorName(e)});
    defer file.close();
    var file_br = std.io.bufferedReader(file.reader());
    const file_r = file_br.reader();

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    const out_w = out.writer();

    var width: u16 = undefined;
    var height: u16 = undefined;
    // FIXME: error handling
    gif.Read(allocator, file_r, out_w, &width, &height) catch return;

    var out_fbs = std.io.fixedBufferStream(out.items);
    const out_r = out_fbs.reader();
    for (0..width * height) |i| {
        // FIXME: error handling?
        const color = out_r.readInt(u32, .Little) catch break; // no more colors
        fpage_new_raw[i] = cf.ConvertMonoRGB(cf.RGBA8888, cf.ARGB4444, color);
    }

    // WARN: causes crash if set to wrong values?? i.e. crash on game load when
    // 1/256 set with stock font enabled
    //rf.gFontPageUnitScaleX.* = @as(f32, 1) / @as(f32, 256);
    //rf.gFontPageUnitScaleY.* = @as(f32, 1) / @as(f32, 256);
}

// WARN: do not use directly; use FontsLoad
fn CustomFontsLoad() void {
    assert(fpage.len >= fonts.len);
    if (fonts_loaded) return;

    // old hd fonts

    for (0..fpage.len) |i| {
        r3.hMaterial_OwnedNewFromData(fpage[i].r, 512, 1024, 512, 1024, .ARGB4444, &fpage[i].t, &fpage[i].m);
    }
    fonts[0]._08_page_list[0] = &fpage[0].m;
    fonts[0]._08_page_list[1] = &fpage[1].m;
    fonts[0]._08_page_list[2] = &fpage[2].m;
    fonts[1]._08_page_list[0] = &fpage[2].m;
    fonts[2]._08_page_list[0] = &fpage[2].m;
    fonts[3]._08_page_list[0] = &fpage[3].m;
    fonts[4]._08_page_list[0] = &fpage[4].m;

    // new custom font framework proof of concept

    r3.hMaterial_OwnedNewFromData(fpage_new.r, 256, 256, 256, 256, .ARGB4444, &fpage_new.t, &fpage_new.m);
    fonts_new[0]._08_page_list[0] = &fpage_new.m;
    // FIXME: need to initialize fonts in a way where "cleanup" like this isn't necessary
    fonts_new[0]._08_page_list[1] = null;
    fonts_new[0]._08_page_list[2] = null;
    fonts_new[1]._08_page_list[0] = &fpage_new.m;
    fonts_new[2]._08_page_list[0] = &fpage_new.m;
    fonts_new[3]._08_page_list[0] = &fpage_new.m;
    fonts_new[4]._08_page_list[0] = &fpage_new.m;
}

// WARN: do not use directly; use FontsUnload
fn CustomFontsUnload() void {
    if (!fonts_loaded) return;

    // OLD NOTES
    // FIXME: works in rendering but still crashes when unloading, in spite
    // of the hMaterial_Free call in OnDeinit; maybe need to force text
    // rendering state to update pointers?
    // maybe worth noting that the game MaterialFree (which hMaterial_Free
    // calls) seems to only ever be called on shutdown or when clearing
    // all sprites when loading Hang menu
    // NOTE: unload crashes at 0x48AA45 (in fn_48AA40) with access violation error
    // (0xC0000005) according to windows event viewer
    // NOTE: all these were originally unique allocations, unlike current
    // scheme that reuses the "base" materials; crash from unload (not re-load)
    // may have just been use-after-free on the duplicated stuff

    // old hd font
    // this one doesn't crash; current ver only crashes in CustomFontsLoad
    for (0..fpage_raw.len) |i| {
        r3.hMaterial_OwnedFree(&fpage[i].m);
    }

    // new custom fonts proof of concept
    r3.hMaterial_OwnedFree(&fpage_new.m);
}

// HOUSEKEEPING

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
    FontState.settingsInit(gf);
}

export fn OnInitLate(_: *GlobalFn) callconv(.C) void {}

export fn OnDeinit(_: *GlobalFn) callconv(.C) void {
    FontsUnload();
}

// HOOKS

export fn TextRenderB(gf: *GlobalFn) callconv(.C) void {
    // NOTE: original function at fn_42D720
    // making sure original fonts are fully loaded before this runs
    if (!fonts_initialized and FontState.s_patch_fonts) {
        FontsInit();
        FontsLoad();
    }

    // toggle custom fonts
    if (fonts_loaded and gf.InputGetKbRaw(.K) == .JustOn) {
        if (fonts_using) {
            fonts_using = false;
            _ = mem.write(0x42D8EE + 3, u32, @intFromPtr(rt.apTextFont));
            _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleX), f32, 1 / 64);
            _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleY), f32, 1 / 128);
        } else {
            fonts_using = true;
            _ = mem.write(0x42D8EE + 3, u32, @intFromPtr(custom_fonts[custom_font_active][0]));
            _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleX), f32, 1 / custom_fonts[custom_font_active][2]);
            _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleY), f32, 1 / custom_fonts[custom_font_active][3]);
        }
    }

    // cycle displayed custom font
    if (fonts_loaded and fonts_using and gf.InputGetKbRaw(.L) == .JustOn) {
        custom_font_active = (custom_font_active + 1) % custom_fonts.len;
        _ = mem.write(0x42D8EE + 3, u32, @intFromPtr(custom_fonts[custom_font_active][0]));
        // factors used to convert texture coordinates to UVs. because all characters
        // use these values regardless of font def, all font pages of a font must be
        // the same size; if not, this value would need to be updated every time a
        // font is selected from the font table, not just when changing the whole table
        _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleX), f32, 1 / custom_fonts[custom_font_active][2]);
        _ = mem.write(@intFromPtr(rf.gFontPageUnitScaleY), f32, 1 / custom_fonts[custom_font_active][3]);
    }

    // testing display showing all(?) font glyphs
    if (gf.InputGetKbRaw(.O).on()) {
        var buf: [255:0]u8 = undefined;
        var x: i16 = 12;
        var y: i16 = 128;

        rt.swrText_CreateEntry1(x, y, 0xFF, 0xFF, 0xFF, 0xFF, "~F0~3~sFONT TEST");
        y += 10;
        const label: ?[*:0]const u8 = std.fmt.bufPrintZ(&buf, "~F4~3~s{s}", .{
            if (fonts_using) custom_fonts[custom_font_active][1] else "base font",
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

    // testing font data dump
    if (gf.InputGetKbRaw(.I) == .JustOn and FontState.s_dump_fonts) {
        FontState.FontDump();
    }

    // for testing load/unload of resources, does not do the ground truth
    // toggle logic
    // - crashes when too many materials loaded/unloaded
    // - "materials" in this case meaning those with the 512x1024 HD font textures
    //   also there is a memory leak here, with N materials ..
    //      N=6     ~1MB leak per cycle
    //      N=10    ~10MB
    //      N=20    ~15MB
    //      N=40    ~35MB
    // - seems to only ever free 5MB regardless of material count
    // - not entirely sure this isn't just a dgvoodoo problem, hard to imagine
    //   such an obvious issue was not caught on original hardware during
    //   dev, could also just be a regression in modern windows vs old directx
    //if (FontState.s_patch_fonts and gf.InputGetKbRaw(.I) == .JustOn) {
    //    if (fonts_loaded) {
    //        FontsUnload();
    //    } else {
    //        // crash at 48A7F4 when 100 textures loaded then unloaded (i.e. 2nd 'I' press)
    //        // in AllocTexture__48A5E0 during vbufferlock memcpy
    //        // with 20 textures loaded, doesn't crash immediately but does crash
    //        // after some number of cycles loading/unloading, and after 3 cycles
    //        // for 40 textures; always around 450MB ram usage
    //        // i.e. seems to just be the memory leak crash?
    //        FontsLoad();
    //    }
    //}
}
