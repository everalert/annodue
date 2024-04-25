const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const json = std.json;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const BuildOptions = @import("BuildOptions");

const zzip = @import("zzip");
const EOCDRecord = zzip.EndOfCentralDirectoryRecord.EndOfCentralDirectoryRecord;
const DirHeader = zzip.CentralDirectoryFileHeader.Header;
const LocHeader = zzip.LocalFileHeader.Header;

const w32 = @import("zigwin32");
const w32wm = w32.ui.windows_and_messaging;

const allocator = @import("Allocator.zig");
const SettingsSt = @import("../settings.zig").SettingsState;
const GlobalSt = @import("../global.zig").GlobalState;
const GlobalFn = @import("../global.zig").GlobalFunction;
const Version = @import("../global.zig").Version;

const r = @import("../util/racer.zig");
const rt = @import("../util/racer_text.zig");

const msg = @import("../util/message.zig");

// BUSINESS LOGIC

// https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28
// https://docs.github.com/en/rest/releases/assets?apiVersion=2022-11-28

// FIXME: extracting should assume directories are denoted by forward slash in
// zip files, as per the zipfile spec; meaning this (the extractor), the packager
// and zzip all need to be updated

const ANNODUE_PATH = if (BuildOptions.BUILD_MODE == .Release) "." else "annodue/tmp/updatetest";

// NOTE: update this list with each new version
// TODO: see about auto-generating this list at comptime, and exposing it via build system
const DELETE_ITEMS = [_][]const u8{
    "plugin",
    "images",
    "textures",
    "annodue.dll",
};

const Update = struct {
    const Self = @This();
    client: http.Client,
    alloc: Allocator,
    ready: bool = false,
    tag: ?[]const u8 = null,
    url: ?[]const u8 = null,
    size: i64 = undefined,

    fn init(alloc: Allocator) Self {
        return .{
            .client = http.Client{ .allocator = alloc },
            .alloc = alloc,
        };
    }

    // FIXME: get this fully deallocating before 0.2.0 release
    fn deinit(self: *Self) void {
        //self.alloc.free(self.tag);
        //self.alloc.free(self.url);
        self.client.deinit();
    }
};

// FIXME: do we even need AnnodueUpdateTagEF struct?
const UPDATE_TAG_EXTRA_FIELD_ID: u16 = 0x5055; // UP

fn updateToastAvailable(alloc: Allocator, gf: *GlobalFn, ver: []const u8) void {
    const new_update_text = std.fmt.allocPrintZ(alloc, "Update Available: {s}", .{ver}) catch return;
    defer alloc.free(new_update_text);
    _ = gf.ToastNew(new_update_text, rt.ColorRGB.Red.rgba(0));
}

// HOOK FUNCTIONS

pub fn OnInitLate(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    const s = struct {
        const retry_delay: u32 = 5 * 60 * 1000; // 5min
        var last_try: u32 = 0;
        var init: bool = false;
    };

    // TODO: http requests crashing in debug builds only; extra option for auto
    // checking for updates at runtime, or just always do it in release and disable
    // entirely for debug builds? doing latter for now..
    if (comptime builtin.mode == .Debug) return;

    // FIXME: remove early AUTO_UPDATE check in future version, once we verify
    // the update system is stable
    if (gf.SettingGetB(null, "AUTO_UPDATE").? == false) return;

    if (s.init or gs.timestamp + s.retry_delay < s.last_try) return;
    s.last_try = gs.timestamp;

    const alloc = allocator.allocator();

    var update = Update.init(alloc);
    defer update.deinit();

    // checking for update
    {
        const api_url = "https://api.github.com/repos/everalert/annodue/releases/latest";
        //const api_url = "https://api.github.com/repos/everalert/annodue/releases/tags/{s}"; // for old ver
        const uri = std.Uri.parse(api_url) catch return;

        var headers = std.http.Headers.init(alloc);
        defer headers.deinit();
        headers.append("accept", "application/vnd.github+json") catch return;
        headers.append("x-github-api-version", "2022-11-28") catch return;

        // NOTE: client.request crash happens here; seems fine in release builds
        // TODO: retry n times, for whole process up to json parsed
        // TODO: settings option for skipping prerelease tags
        var request = update.client.request(.GET, uri, headers, .{}) catch return;
        defer request.deinit();
        request.start() catch return;
        request.wait() catch return;
        if (request.response.status != .ok) return;

        const body = request.reader().readAllAlloc(alloc, 1 << 31) catch return;
        defer alloc.free(body);

        const parsed = json.parseFromSlice(json.Value, alloc, body, .{}) catch return;
        defer parsed.deinit();

        // TODO: extra check + setting for opting in to debug releases?
        const tag = parsed.value.object.get("tag_name").?.string;
        update.tag = alloc.dupe(u8, tag) catch return;
        const tag_ver = std.SemanticVersion.parse(update.tag.?) catch return;
        if (std.SemanticVersion.order(Version, tag_ver) != .lt) return;

        s.init = true; // at this point it doesn't matter if we can dl or not

        // TODO: use label too in future?
        const assets = parsed.value.object.get("assets").?.array;
        for (assets.items) |asset| {
            // for now: filename ends with "update.zip", e.g. annodue-0.1.0-update.zip
            // future: same file as release zip, annodue-<semver>.zip
            const name = asset.object.get("name").?.string;
            if (!std.mem.endsWith(u8, name, "-update.zip")) continue;

            const state = asset.object.get("state").?.string;
            if (!std.mem.eql(u8, state, "uploaded")) return; // we know we can't update now

            const url = asset.object.get("browser_download_url").?.string;
            update.url = alloc.dupe(u8, url) catch return;
            update.size = asset.object.get("size").?.integer;
            break;
        }

        if (update.url == null) return;
    }

    updateToastAvailable(alloc, gf, update.tag.?);

    if (gf.SettingGetB(null, "AUTO_UPDATE").? == false) return;

    updateApplyFromNetwork(alloc, &update) catch return;

    // -> notify user to restart game
    msg.StdMessage("Annodue {s} installed\n\nPlease restart Episode I Racer", .{update.tag.?});
    _ = w32wm.PostMessageA(@ptrCast(gs.hwnd), w32wm.WM_CLOSE, 0, 0);
}

// FIXME: remove, or convert to proper system for manual updating
pub fn EarlyEngineUpdateB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    if (BuildOptions.BUILD_MODE == .Developer) {
        if (gf.InputGetKb(.U, .JustOn))
            OnInitLate(gs, gf);

        if (gf.InputGetKb(.J, .JustOn)) {
            const alloc = allocator.allocator();
            const fp = std.fmt.allocPrint(alloc, "{s}/{s}", .{ ANNODUE_PATH, "update.zip" }) catch return;
            defer alloc.free(fp);
            const f = std.fs.cwd().openFile(fp, .{}) catch return;
            defer f.close();
            const raw_data = f.readToEndAlloc(alloc, 1 << 31) catch return;
            defer alloc.free(raw_data);
            updateApplyFromZipData(alloc, raw_data) catch return;
        }
    }
}

// FIXME: below should be the last piece before github releases test.
// final review and test update process with local file instead of download.
// don't forget to update version in global.zig before compiling for github.
fn updateApplyFromNetwork(alloc: Allocator, update: *Update) !void {
    // -> download update.zip from the release
    while (true) {
        const uri = std.Uri.parse(update.url.?) catch |e| return e;

        var headers = std.http.Headers.init(alloc);
        defer headers.deinit();
        headers.append("accept", "application/octet-stream") catch |e| return e;

        var request = update.client.request(.GET, uri, headers, .{}) catch |e| return e;
        defer request.deinit();
        request.start() catch |e| return e;
        request.wait() catch |e| return e;

        // for now: filename ends with "update.zip", e.g. annodue-0.1.0-update.zip
        //    only includes update files + "minver.txt" (<semver>\n<release_api_url>)
        //    internal dir structure equivalent to /annodue/*
        // future: same file as release zip, annodue-<semver>.zip
        //    packed files use extra field to identify which to extract
        if (request.response.status == .ok) {
            const raw_data = request.reader().readAllAlloc(alloc, 1 << 31) catch |e| return e;
            defer alloc.free(raw_data);

            // -> verify download succeeded/packed data is valid somehow?
            // TODO: confirm if anything (else?) even needs to be done at this point to
            // know that the data was properly received
            if (update.size != raw_data.len) return error.InvalidHttpDataSize;

            return updateApplyFromZipData(alloc, raw_data);
        }

        if (request.response.status == .found) {
            // TODO: case checking? tho github api seems to return lowercase headers
            if (request.response.headers.getFirstValue("location")) |loc| {
                update.url = loc;
                continue;
            }
        }

        return error.InvalidHttpResponse;
    }
}

// TODO: MINVER.txt validation
// TODO: check update dependencies and recursively download until
// finding a valid update version (impl after 0.1.0 release)
// FIXME: (ZZIP) impl zip unpacking changes (slash correction) into zzip lib
// FIXME: (ZZIP) impl a decent canned way of doing this into zzip lib
fn updateApplyFromZipData(alloc: Allocator, raw_data: []const u8) !void {
    // -> delete relevant files in file system
    // TODO: maybe don't delete in future; depends on plugin ecosystem
    for (DELETE_ITEMS) |path| {
        const p = std.fmt.allocPrintZ(alloc, "{s}/{s}", .{ ANNODUE_PATH, path }) catch |e| return e;
        defer alloc.free(p);
        std.fs.cwd().deleteTree(p) catch |e| return e;
    }

    // -> unpack files to file system
    // TODO: switch to using annodue update tag to tell when to actually unpack/not skip
    // FIXME: error handling in case writing new files fails; re-download
    // old version and restore that way? make a copy of the old files in tmp
    // and track new stuff in order to go backward?
    const eocd = EOCDRecord.parse(raw_data) catch |e| return e;
    var dir_it = DirHeader.iterator(&eocd);
    while (dir_it.next()) |df| {
        const lf = LocHeader.parse(raw_data[df.local_header_offset..], raw_data) catch |e| return e;
        // TODO: make some kind of comptime assurance that it will be a particular kind of slash
        if (!std.mem.startsWith(u8, lf.filename, "annodue/")) continue;

        // TODO: do something in zzig about this crap
        const data_off: usize = df.local_header_offset + 30 + lf.len_filename + lf.len_extra_field;
        const data = raw_data[data_off .. data_off + lf.size_compressed];

        // TODO: make some kind of comptime assurance that it will be a particular kind of slash
        const fp = std.fmt.allocPrint(alloc, "{s}/{s}", .{ ANNODUE_PATH, lf.filename }) catch return;
        if (std.mem.lastIndexOf(u8, fp, "/")) |end|
            std.fs.cwd().makePath(fp[0..end]) catch |e| return e;

        defer alloc.free(fp);
        const out = std.fs.cwd().createFile(fp, .{}) catch |e| return e;
        defer out.close();
        lf.compression.uncompress(alloc, data, out.writer(), df.crc32) catch |e| return e;
    }
}
