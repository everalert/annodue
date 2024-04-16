const BuildOptions = @import("BuildOptions");

const std = @import("std");
const http = std.http;
const json = std.json;

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

// FIXME: remove
const TestMessage = msg.TestMessage;

pub fn EarlyEngineUpdateB(gs: *GlobalSt, gf: *GlobalFn) callconv(.C) void {
    const s = struct {
        var init: bool = false;
        var buf: [127:0]u8 = undefined;
    };

    //if (s.init) return;
    if (!gf.InputGetKb(.U, .JustOn)) return;
    // TODO: http requests crashing in debug builds only; extra option for auto
    // checking for updates at runtime, or just always do it in release and disable
    // entirely for debug builds? doing latter for now..
    if (BuildOptions.OPTIMIZE == .Debug) return;

    const alloc = allocator.allocator();

    // checking for update

    var client = http.Client{ .allocator = alloc };
    defer client.deinit();

    const api_url: []const u8 = "https://api.github.com/repos/ziglang/zig/releases/latest";
    //const api_url: []const u8 = "https://api.github.com/repos/everalert/annodue/releases/latest";
    const uri = std.Uri.parse(api_url) catch return;

    var headers = std.http.Headers.init(alloc);
    defer headers.deinit();
    headers.append("accept", "application/vnd.github+json") catch return;
    headers.append("x-github-api-version", "2022-11-28") catch return;

    // NOTE: client.request crash happens here; seems fine in release builds
    // TODO: retry n times, for whole process up to json parsed
    // TODO: settings option for skipping prerelease tags
    var request = client.request(.GET, uri, headers, .{}) catch return;
    defer request.deinit();
    request.start() catch return;
    request.wait() catch return;
    if (request.response.status != .ok) return;

    const body = request.reader().readAllAlloc(alloc, 1 << 31) catch return;
    defer alloc.free(body);

    const parsed = json.parseFromSlice(json.Value, alloc, body, .{}) catch return;
    defer parsed.deinit();

    const tag = parsed.value.object.get("tag_name").?.string;
    //const tag: []const u8 = "1.1.1";
    const tag_ver = std.SemanticVersion.parse(tag) catch return;
    if (std.SemanticVersion.order(Version, tag_ver) != .lt) return;

    s.init = true;

    // downloading and installing new update

    // -> check settings for AUTO_UPDATE
    if (gf.SettingGetB(null, "AUTO_UPDATE").? == false) {
        _ = std.fmt.bufPrintZ(&s.buf, "Update Available: {s}", .{tag}) catch return;
        _ = gf.ToastNew(&s.buf, rt.ColorRGB.Red.rgba(0));
        return;
    }

    // -> download update.zip from the release

    // -> verify download succeeded/packed data is valid somehow?

    // -> delete relevant files in file system

    // -> unpack files to file system

    // -> notify user to restart game
    msg.StdMessage("Annodue {s} installed\n\nPlease restart Episode I Racer", .{tag});
    _ = w32wm.PostMessageA(@ptrCast(gs.hwnd), w32wm.WM_CLOSE, 0, 0);
}
