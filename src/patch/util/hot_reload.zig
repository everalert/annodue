const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const w32 = @import("zigwin32");
const w32f = w32.foundation;
const w32fs = w32.storage.file_system;

// FIXME: todos before moving back to finalize font stuff..
//  - actually use this for all existing hot-reload sites
//  - review and impl the below todo/fixme as appropriate
//  - if it seems easy, impl the different versions (at least the single-file ver)
//  - add tests
//  - add docs (particularly top-level docs comment summary)
//  - after finalizing, don't forget to actually try using this for fonts lol

// TODO: version which monitors a whole directory, and can handle cases such as
//  new files, file deletion, etc. to dynamically adapt the hot reload list, rather
//  than making a list and querying the files individually
// TODO: simplified version which operates on a single file only, as a convenience
//  for sites like ASettings that only ever track one file

// FIXME: currently this doesn't protect against duplicate file listings
// TODO: ?? impl "skip next load" (like ASettings) as part of hot-reloader
// TODO: ?? callback for post-load action to handle different success states
// TODO: ?? manage tracked files via handles
// TODO: ?? add unload callback; will need to be called on deinit and in the various Untrack fns
// TODO: ?? impl the following
//  pub fn TrackDirectory() void {} // batch add files from directory; needs some method to filter files
//  pub fn UntrackDirectory() void {}
//  pub fn UntrackAll() void {}
/// @ContextHandleT      reference to data associated with the file being tracked,
///                      typically a struct pointer but may be an opaque handle
///                      such as an array index, or void to "pass" on context
pub fn HotReload(comptime ContextHandleT: type) type {
    return struct {
        const HotReloadT = @This();

        FileList: ArrayList(FileRecord) = undefined,

        CheckDelay: u32 = 40, // 25fps in ms
        CheckTimestamp: u32 = 0,
        CheckIndex: usize = 0,

        // TODO: return error instead of null? (e.g. error{LoadAborted})
        /// callback for loading the hot-reload target. this will run both when
        /// loading the target initially, and when hot-reloading
        /// @return     null  = load aborted
        ///             true  = load successful
        ///             false = load failure
        fnLoad: LoadCallback = undefined,

        const LoadCallback = *const fn (ctx: ContextHandleT, filename: [*:0]const u8) ?bool;

        pub fn Init(gpa: Allocator, fn_load: LoadCallback) HotReloadT {
            return HotReloadT{
                .FileList = std.ArrayList(FileRecord).init(gpa),
                .fnLoad = fn_load,
            };
        }

        pub fn Deinit(self: *HotReloadT) void {
            self.FileList.deinit();
        }

        pub fn Update(self: *HotReloadT, timestamp: u32) void {
            if (timestamp < self.CheckTimestamp + self.CheckDelay) return;

            const item = &self.FileList.items[self.CheckIndex];
            if (!item.Check()) return;

            // TODO: callback to handle fnLoad return
            _ = self.fnLoad(item.Context, &item.FilePath);

            self.CheckIndex = (self.CheckIndex + 1) % self.FileList.items.len;
            self.CheckTimestamp = timestamp;
        }

        // TODO: ?? error result may be more appropriate for differentiating the
        //  types of failure?
        /// adds a file to track for hot reloading and runs load callback on it.
        /// adding the file will always succeed, even if the file couldn't load.
        /// @return     true if `fnLoad` runs and completes successfully. false
        ///             may indicate that `fnLoad` failed, or that the file was
        ///             not readable in the first place.
        pub fn TrackFile(self: *HotReloadT, filename: [*:0]const u8, ctx: ContextHandleT) bool {
            var record: *FileRecord = self.FileList.addOne() catch return false;

            if (!record.Init(filename, ctx)) return false;

            // TODO: callback to handle fnLoad return state
            const load_result = self.fnLoad(ctx, filename);
            return !(load_result == null or load_result.? == false);
        }

        pub fn UntrackFile(self: *HotReloadT, filename: [*:0]const u8) void {
            for (0..self.FileList.items.len) |i| {
                if (std.mem.orderZ(u8, filename, &self.FileList.items[i].FileName) == .eq) {
                    _ = self.FileList.swapRemove(i);
                    self.CheckIndex %= self.FileList.items.len;
                    break;
                }
            }
        }

        pub const FileRecord = struct {
            Context: ContextHandleT,
            FilePath: [w32f.MAX_PATH - 1:0]u8,
            FileSizeLow: u32 = 0,
            FileSizeHigh: u32 = 0,
            WriteTimeLow: u32 = 0,
            WriteTimeHigh: u32 = 0,

            const FileRecordError = error{ DataGetFailed, FileNameTooLong };

            /// will always clear and initialize the record. if the file is not
            /// readable, the time/size info will remain cleared to 0
            /// @return     whether the file was actually readable
            pub fn Init(record: *FileRecord, filename: [*:0]const u8, ctx: ContextHandleT) bool {
                record.* = std.mem.zeroes(FileRecord);
                _ = std.fmt.bufPrintZ(&record.FilePath, "{s}", .{filename}) catch unreachable;
                record.Context = ctx;

                var fd: w32fs.WIN32_FIND_DATAA = undefined;
                if (!DataGet(filename, &fd)) return false;

                record.DataWrite(&fd);
                return true;
            }

            /// checks the file and updates the record if needed
            /// @return     whether or not the file appears to have changed
            pub fn Check(self: *FileRecord) bool {
                var fd: w32fs.WIN32_FIND_DATAA = undefined;
                if (!DataGet(&self.FilePath, &fd)) return false;

                if (self.WriteTimeLow == fd.ftLastWriteTime.dwLowDateTime and
                    self.FileSizeLow == fd.nFileSizeLow and
                    self.WriteTimeHigh == fd.ftLastWriteTime.dwHighDateTime and
                    self.FileSizeHigh == fd.nFileSizeHigh)
                    return false;

                DataWrite(self, &fd);
                return true;
            }

            pub fn DataWrite(self: *FileRecord, fd: *const w32fs.WIN32_FIND_DATAA) void {
                self.WriteTimeLow = fd.ftLastWriteTime.dwLowDateTime;
                self.WriteTimeHigh = fd.ftLastWriteTime.dwHighDateTime;
                self.FileSizeLow = fd.nFileSizeLow;
                self.FileSizeHigh = fd.nFileSizeHigh;
            }

            pub fn DataGet(filename: [*:0]const u8, fd: *w32fs.WIN32_FIND_DATAA) bool {
                if (std.mem.len(filename) >= w32f.MAX_PATH) return false;

                const find_handle = w32fs.FindFirstFileA(filename, fd);
                defer _ = w32fs.FindClose(find_handle);
                return (-1 != find_handle);
            }
        };
    };
}

//------------------------------------------------------------------------------
// ref: ASettings.zig

//-------------------------------------
// from GameLoopB

//if (rti.TIMESTAMP.* > ASettings.last_check + ASettings.check_freq)
//    _ = ASettings.load();
//ASettings.last_check = rti.TIMESTAMP.*;

//-------------------------------------
// from ASettings.load

//if (!filetime_checkNewerWriteTime(FILENAME_ACTIVE, &ASettings.last_filetime))
//    return false;

//if (skip_next_load) {
//    skip_next_load = false;
//    return false;
//}

//ASettings.iniRead(coreAllocator(), FILENAME_ACTIVE) catch return false;

//file_exists = true;
//return true;

//------------------------------------------------------------------------------
// ref: Hook.zig

//pub const PluginState = struct {
//    const check_freq: u32 = 1000 / 24; // in lieu of every frame
//    var last_check: u32 = 0;
//    var core: std.ArrayList(Plugin) = undefined;
//    var plugin: std.ArrayList(Plugin) = undefined;
//    var hot_reload_i: usize = 0;
//};

//-------------------------------------
// from Hook.zig init()

//const cwd = std.fs.cwd();
//var dir = cwd.openIterableDir("./annodue/plugin", .{}) catch
//    cwd.makeOpenPathIterable("./annodue/plugin", .{}) catch @panic("failed to open plugin directory");
//defer dir.close();

//var it_dir = dir.iterate();
//while (it_dir.next() catch @panic("failed to fetch next plugin")) |file| {
//    if (file.kind != .file) continue;
//    if (!std.mem.eql(u8, ".DLL", file.name[file.name.len - 4 ..]) and
//        !std.mem.eql(u8, ".dll", file.name[file.name.len - 4 ..])) continue;

//    p = PluginState.plugin.addOne() catch @panic("failed to add user plugin to arraylist");
//    p.* = std.mem.zeroInit(Plugin, .{});
//    const load = LoadPlugin(p, file.name);
//    if (load != null and !load.?)
//        _ = PluginState.plugin.pop();
//}

//-------------------------------------
// from Hook.zig GameLoopB

//if (PluginState.s_hot_reload and rti.TIMESTAMP.* > PluginState.last_check + PluginState.check_freq) {
//    PluginState.last_check = rti.TIMESTAMP.*;
//    PluginState.hot_reload_i = (PluginState.hot_reload_i + 1) % PluginState.plugin.items.len;
//    const p: *Plugin = &PluginState.plugin.items[PluginState.hot_reload_i];

//    const len = for (p.Filename, 0..) |c, j| {
//        if (c == 0) break j;
//    } else p.Filename.len;
//    const load = LoadPlugin(p, p.Filename[0..len]);

//    if (load == null) return;

//    if (load.?) {
//        var buf: [127:0]u8 = undefined;
//        _ = std.fmt.bufPrintZ(&buf, "Plugin Loaded: {s}", .{p.PluginName.?()}) catch return;
//        _ = gf.ToastNew(&buf, r.Text.ColorRGB.Green.rgba(0));
//    } else {
//        _ = PluginState.plugin.swapRemove(PluginState.hot_reload_i);
//    }
//}
