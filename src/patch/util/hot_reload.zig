const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Wyhash = std.hash.Wyhash;
const assert = std.debug.assert;
const panic = std.debug.panic;

const w32 = @import("zigwin32");
const FILETIME = w32.foundation.FILETIME;
const MAX_PATH = w32.foundation.MAX_PATH;
const MAX_PATH_SENTINEL = MAX_PATH - 1;
const WIN32_FIND_DATAA = w32.storage.file_system.WIN32_FIND_DATAA;
const FindFirstFileA = w32.storage.file_system.FindFirstFileA;
const FindClose = w32.storage.file_system.FindClose;

// FIXME: todos before moving back to finalize font stuff..
//  - add tests (at least one to demonstrate usage; if punting test thoroughness, make todos for them)
//  - probably also abstract out Plugins from Hook and clean up that API
//  - after finalizing, don't forget to actually try using this for fonts lol

// FIXME: currently this doesn't protect against duplicate file listings. not sure
//  if they should be prevented from the jump, or if that should be an option. not
//  urgent until whole-directory monitoring impl
// TODO: version which monitors a whole directory, and can handle cases such as
//  new files, file deletion, etc. to dynamically adapt the hot reload list, rather
//  than making a list and querying the files individually. see: ReadDirectoryChangesW/-ExW
// TODO: version which takes an allocator (and uses a hashmap)? avoided this before
//  because my use case didn't need much memory, but might be worth keeping in mind
// TODO: add fnUnload callback (and accompanying fnUnloadResult)
//  - call on deinit, in untrack functions, during whole-directory monitoring
// TODO: option/function to check all files in an update; not sure if looping
//  behaviour is actually necessary for performance, need to verify with testers
// TODO: deinit impl that batch-untracks the file list
// TODO: ?? add scoped logging
// TODO: ?? manage tracked files via handles
// TODO: ?? add load time to FileRecord? to differentiate between checking and successful load
// TODO: ?? impl the following for convenience
//  pub fn TrackDirectory() void {} // batch add files from directory; needs some method to filter files
//  pub fn UntrackDirectory() void {}
//  pub fn UntrackAll() void {}
// TODO: ?? non-windows impls?
/// API for monitoring and responding to file changes.
///
/// WARN: impl is windows-only
///
/// This implementation is entirely static and does not require the user to manage
/// its memory; the user need only specify a maximum number for files to track and
/// provide the bytes upfront. Any additional data needed for each file beyond the
/// file monitoring functionality must be managed externally, and is associated with
/// the API via user-provided handles.
///
///     1. Configure the type via `HotReload`.
///         - If no external data is needed, typical usage is to set the context handle
///           type to `u32` and pass `0` to any subsequent `TrackFile*` calls.
///     2. Setup with `Init`.
///         - `LoadCallback`:
///             - runs when initially adding the file for tracking.
///             - runs if a file changes (it can assume the file is new).
///             - must also handle any "unloading" needed during an update.
///         - Optional config via `fnLoadResultCallback` and `CheckDelay` fields.
///     3. Add files to monitor via `TrackFile` and `TrackFileAlways`.
///     4. Run `Update` at a regularly-executing callsite to monitor for changes.
///         - `timestamp` is "unit-less"; timescale is up to the user. `CheckDelay`
///           assumes the same units as `timestamp`/`CheckTimestamp`.
///         - Only one file is updated per run in a looping fashion, to reduce OS load.
///     5. Cleanup files with `UntrackFile`.
///
/// @ContextHandleT     reference to data associated with the file being tracked,
///                     typically a struct pointer but may be an opaque handle
///                     such as an array index, or void to "pass" on context
/// @ITEM_MAX           max number of trackable items, statically allocated
pub fn HotReload(comptime ContextHandleT: type, comptime ITEM_MAX: usize) type {
    return struct {
        const HotReloadT = @This();

        /// internal
        FileList: [ITEM_MAX]FileRecord = undefined,
        /// internal
        FileListUsed: [ITEM_MAX]bool = std.mem.zeroes([ITEM_MAX]bool),
        /// internal
        FileListCount: usize = 0,

        /// callback for loading the hot-reload target. this will run both when
        /// loading the target initially and when hot-reloading, and will need to
        /// handle unloading if necessary
        /// @return     true if load successful
        fnLoad: LoadCallback,
        /// callback for running any post-processing after a load attempt. this
        /// is intended as an option for cleanly separating "reactive" loading
        /// logic from "active", such as resource cleanup or sending UI notifications.
        fnLoadResult: ?LoadResultCallback = null,

        /// minimum wait time before a new update can run, in `CheckTimestamp` units
        CheckDelay: usize = 0,
        /// timestamp of previous update, in user-defined units
        CheckTimestamp: usize = 0,
        /// internal: next item to be checked for changes
        CheckIndex: usize = 0,

        // TODO: ?? return an enum for more result state granularity?
        const LoadResultT = bool;
        /// ctx, filepath, filename
        const LoadCallback = *const fn (ContextHandleT, [:0]const u8, [:0]const u8) LoadResultT;
        /// ctx, filepath, filename, result
        const LoadResultCallback = *const fn (ContextHandleT, [:0]const u8, [:0]const u8, LoadResultT) void;

        pub fn Init(self: *HotReloadT, fn_load: LoadCallback) void {
            self.* = std.mem.zeroInit(HotReloadT, .{ .fnLoad = fn_load });
        }

        pub fn Update(self: *HotReloadT, timestamp: usize) void {
            if (timestamp < self.CheckTimestamp + self.CheckDelay) return;
            if (self.FileListCount == 0) return;
            defer _ = if (comptime ITEM_MAX > 1) {
                self.CheckIndex = (self.CheckIndex + 1) % ITEM_MAX;
                self.CheckTimestamp = timestamp;
            };

            if (comptime ITEM_MAX > 1) {
                while (!self.FileListUsed[self.CheckIndex])
                    self.CheckIndex = (self.CheckIndex + 1) % ITEM_MAX;
            }

            const item = &self.FileList[self.CheckIndex];
            if (!item.Check()) return;

            const result = self.fnLoad(item.Context, item.FilePathSlice(), item.FileNameSlice());
            if (self.fnLoadResult) |f| f(item.Context, item.FilePathSlice(), item.FileNameSlice(), result);
        }

        /// adds a file to track for hot reloading, and runs the load-related
        /// callbacks. if the loading process fails for any reason, the file will
        /// not be added to the tracking list.
        /// @return     true when the callbacks successfully run; on false, any
        ///             failure case dependent on `fnLoadResult` will not be
        ///             handled, so the caller may need to do manual cleanup
        pub fn TrackFile(self: *HotReloadT, filepath: [*:0]const u8, ctx: ContextHandleT) bool {
            const file_slot = self.GetFreeFileSlot() orelse return false;
            var record: *FileRecord = &self.FileList[file_slot];

            if (!record.Init(filepath, ctx)) return false;
            const result = self.fnLoad(ctx, record.FilePathSlice(), record.FileNameSlice());
            if (self.fnLoadResult) |f| f(ctx, record.FilePathSlice(), record.FileNameSlice(), result);

            if (result) {
                self.FileListCount += 1;
                self.FileListUsed[file_slot] = true;
            }

            return true;
        }

        /// adds a file to track for hot reloading, and runs the load-related
        /// callbacks on it if possible. the file will always be added to the
        /// tracking list, even if the file doesn't exist yet
        pub fn TrackFileAlways(self: *HotReloadT, filepath: [*:0]const u8, ctx: ContextHandleT) void {
            const file_slot = self.GetFreeFileSlot() orelse @panic("TrackFileAlways: item capacity exceeded");
            var record: *FileRecord = &self.FileList[file_slot];

            self.FileListCount += 1;
            self.FileListUsed[file_slot] = true;

            if (!record.Init(filepath, ctx)) return;
            const result = self.fnLoad(ctx, record.FilePathSlice(), record.FileNameSlice());
            if (self.fnLoadResult) |f| f(ctx, record.FilePathSlice(), record.FileNameSlice(), result);
        }

        pub fn UntrackFile(self: *HotReloadT, filepath: [*:0]const u8) void {
            for (0..ITEM_MAX) |i| {
                if (std.mem.orderZ(u8, filepath, &self.FileList[i].FilePath) == .eq) {
                    assert(self.FileListUsed[i]);
                    assert(self.FileListCount > 0);
                    self.FileListUsed[i] = false;
                    self.FileListCount -= 1;
                    break;
                }
            }
        }

        fn GetFreeFileSlot(self: *HotReloadT) ?usize {
            if (self.FileListCount == ITEM_MAX) return null;

            for (0..ITEM_MAX) |i|
                if (!self.FileListUsed[i])
                    return i;

            unreachable;
        }

        // TODO: ?? option to disable/skip file hash check, as a perf option
        // TODO: ?? also check for file size; still not 100% sure it was good to drop
        const FileRecord = struct {
            Context: ContextHandleT,
            FilePath: [MAX_PATH_SENTINEL:0]u8,
            FilePathLen: usize,
            FileNameLen: usize,
            FileHash: u64 = 0,
            WriteTimeL: u32 = 0,
            WriteTimeH: u32 = 0,

            /// will always zero and initialize the record with the filename and
            /// context. if the file is not readable, the write time and hash may
            /// not be filled out
            /// @return     true if file info was read successfully
            pub fn Init(record: *FileRecord, filepath: [*:0]const u8, ctx: ContextHandleT) bool {
                assert(std.mem.len(filepath) <= MAX_PATH_SENTINEL);

                record.* = std.mem.zeroes(FileRecord);
                record.Context = ctx;

                _ = std.fmt.bufPrintZ(&record.FilePath, "{s}", .{filepath}) catch unreachable;
                record.FilePathLen = std.mem.len(@as([*:0]const u8, &record.FilePath));
                const fn_st = std.mem.lastIndexOfScalar(u8, record.FilePathSlice(), '/');
                const fn_st_v = if (fn_st) |st| st + 1 else 0;
                record.FileNameLen = record.FilePathLen - fn_st_v;

                var fd: WIN32_FIND_DATAA = undefined;
                if (!DataGet(filepath, &fd)) return false;

                var h: u64 = undefined;
                if (!HashGet(record.FilePathSlice(), &h)) return false;

                record.FileHash = h;
                record.DataWrite(&fd);
                return true;
            }

            /// checks the file and updates the record if needed
            /// @return     true if file has changed
            pub fn Check(self: *FileRecord) bool {
                var fd: WIN32_FIND_DATAA = undefined;
                if (!DataGet(&self.FilePath, &fd)) return false;
                if (self.WriteTimeL == fd.ftLastWriteTime.dwLowDateTime and
                    self.WriteTimeH == fd.ftLastWriteTime.dwHighDateTime)
                    return false;

                var h: u64 = undefined;
                if (!HashGet(self.FilePathSlice(), &h)) return false;
                if (self.FileHash == h) return false;

                self.FileHash = h;
                DataWrite(self, &fd);
                return true;
            }

            fn HashGet(filepath: []const u8, h: *u64) bool {
                var f = std.fs.cwd().openFile(filepath, .{}) catch return false;
                defer f.close();
                const f_r = f.reader();

                var wh = Wyhash.init(0);
                var buf_f: [4096]u8 = undefined;
                var buf_f_read = f_r.read(&buf_f) catch return false;
                while (buf_f_read > 0) {
                    wh.update(buf_f[0..buf_f_read]);
                    buf_f_read = f_r.read(&buf_f) catch return false;
                }

                h.* = wh.final();
                return true;
            }

            fn DataGet(filepath: [*:0]const u8, fd: *WIN32_FIND_DATAA) bool {
                if (std.mem.len(filepath) > MAX_PATH_SENTINEL) return false;

                const find_handle = FindFirstFileA(filepath, fd);
                defer _ = FindClose(find_handle); // TODO: hold onto the handle and reuse instead?
                return (-1 != find_handle);
            }

            fn DataWrite(self: *FileRecord, fd: *const WIN32_FIND_DATAA) void {
                self.WriteTimeL = fd.ftLastWriteTime.dwLowDateTime;
                self.WriteTimeH = fd.ftLastWriteTime.dwHighDateTime;
            }

            fn FilePathSlice(self: *const FileRecord) [:0]const u8 {
                return self.FilePath[0..self.FilePathLen :0];
            }

            fn FileNameSlice(self: *const FileRecord) [:0]const u8 {
                return self.FilePath[self.FilePathLen - self.FileNameLen .. self.FilePathLen :0];
            }
        };
    };
}
