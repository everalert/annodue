const std = @import("std");
const builtin = @import("builtin");

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
//  - add tests (at least one to demonstrate usage; if punting test thoroughness,
//    make todos for them). update: even a demo test probably requires reworking
//    the util to be platform-agnostic for the sake of mocking, maybe just punt
//    the whole thing until coming back to this since it should be soon enough.
//    update2: might be fun to do now since the OS stuff is already semi segregated.
//      notes/ideas:
//      - in FileEntry, change WIN32_FIND_DATAA field to new general type that holds
//        write time and hash, and filesize in future if needed. write time common
//        type becomes u64 (win: FILETIME->u64, linux: i64->u64)
//      - HashGet and DataGet get abstracted away to OS-agnostic interface, which
//        is selected at comptime; maybe also change/rename DataWrite to make it
//        conceptually distinct from the direct-OS stuff
//      - atp can probably also greatly simplify FileEntry and do all the "real
//        logic" in HotReload
//      - apparently std has an os abstraction over the raw data (see: std.os.stat/std.fs.stat)
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
    const functions: struct {
        FileData.InfoGetFnT,
        FileData.HashGetFnT,
    } = switch (builtin.os.tag) {
        .windows => .{ FileData.InfoGetWin32, FileData.HashGetWin32 },
        else => @compileError("unsupported target"),
    };

    return HotReloadInternal(ContextHandleT, ITEM_MAX, functions[0], functions[1]);
}

fn HotReloadInternal(
    comptime ContextHandleT: type,
    comptime ITEM_MAX: usize,
    comptime fnFileInfoGet: FileData.InfoGetFnT,
    comptime fnFileHashGet: FileData.HashGetFnT,
) type {
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

        const FileRecord = FileRecordInternal(ContextHandleT, fnFileInfoGet, fnFileHashGet);

        pub fn Init(self: *HotReloadT, fn_load: LoadCallback) void {
            self.* = std.mem.zeroInit(HotReloadT, .{ .fnLoad = fn_load });
        }

        pub fn Update(self: *HotReloadT, timestamp: usize) void {
            if (self.FileListCount == 0) return;

            if (timestamp <= self.CheckTimestamp + self.CheckDelay) return;
            self.CheckTimestamp = timestamp;

            defer _ = if (comptime ITEM_MAX > 1) {
                self.CheckIndex = (self.CheckIndex + 1) % ITEM_MAX;
            };

            if (comptime ITEM_MAX > 1) {
                while (!self.FileListUsed[self.CheckIndex])
                    self.CheckIndex = (self.CheckIndex + 1) % ITEM_MAX;
            }

            const item = &self.FileList[self.CheckIndex];
            if (!item.Check()) return;

            const result = self.fnLoad(item.Context, item.PathSlice(), item.NameSlice());
            if (self.fnLoadResult) |f| f(item.Context, item.PathSlice(), item.NameSlice(), result);
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
            const result = self.fnLoad(ctx, record.PathSlice(), record.NameSlice());
            if (self.fnLoadResult) |f| f(ctx, record.PathSlice(), record.NameSlice(), result);

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
            const result = self.fnLoad(ctx, record.PathSlice(), record.NameSlice());
            if (self.fnLoadResult) |f| f(ctx, record.PathSlice(), record.NameSlice(), result);
        }

        pub fn UntrackFile(self: *HotReloadT, filepath: [*:0]const u8) void {
            for (0..ITEM_MAX) |i| {
                if (std.mem.orderZ(u8, filepath, &self.FileList[i].Path) == .eq) {
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
    };
}

// TODO: ?? option to disable/skip file hash check, as a perf option
// TODO: ?? also check for file size; still not 100% sure it was good to drop
fn FileRecordInternal(
    comptime ContextHandleT: type,
    comptime fnFileInfoGet: FileData.InfoGetFnT,
    comptime fnFileHashGet: FileData.HashGetFnT,
) type {
    return struct {
        const FileRecordT = @This();

        Context: ContextHandleT,
        Path: [MAX_PATH_SENTINEL:0]u8,
        PathLen: usize,
        NameLen: usize,
        Data: FileData,

        /// will always zero and initialize the record with the filename and
        /// context. if the file is not readable, the write time and hash may
        /// not be filled out
        /// @return     true if file info was read successfully
        pub fn Init(record: *FileRecordT, filepath: [*:0]const u8, ctx: ContextHandleT) bool {
            assert(std.mem.len(filepath) <= MAX_PATH_SENTINEL);

            record.* = std.mem.zeroes(FileRecordT);
            record.Context = ctx;

            _ = std.fmt.bufPrintZ(&record.Path, "{s}", .{filepath}) catch unreachable;
            record.PathLen = std.mem.len(@as([*:0]const u8, &record.Path));
            const fn_st = std.mem.lastIndexOfScalar(u8, record.PathSlice(), '/');
            const fn_st_v = if (fn_st) |st| st + 1 else 0;
            record.NameLen = record.PathLen - fn_st_v;

            var fd: FileData = .{};
            if (!fnFileInfoGet(&fd, record.PathSlice())) return false;
            if (!fnFileHashGet(&fd, record.PathSlice())) return false;

            record.Data = fd;
            return true;
        }

        /// checks the file and updates the record if needed
        /// @return     true if file has changed
        pub fn Check(self: *FileRecordT) bool {
            var fd: FileData = .{};

            if (!fnFileInfoGet(&fd, self.PathSlice())) return false;
            if (self.Data.WriteTime == fd.WriteTime) return false;

            if (!fnFileHashGet(&fd, self.PathSlice())) return false;
            if (self.Data.Hash == fd.Hash) return false;

            self.Data = fd;
            return true;
        }

        pub fn PathSlice(self: *const FileRecordT) [:0]const u8 {
            return self.Path[0..self.PathLen :0];
        }

        pub fn NameSlice(self: *const FileRecordT) [:0]const u8 {
            return self.Path[self.PathLen - self.NameLen .. self.PathLen :0];
        }
    };
}

const FileData = struct {
    WriteTime: u64 = 0,
    Hash: u64 = 0,

    /// retrieves the last write time of `filepath`, and places it into `self.WriteTime`
    /// @return     if true, the write time was successfully retrieved
    const InfoGetFnT = fn (*FileData, [:0]const u8) bool;

    /// calculates the hash of `filepath`s contents, and places it into `self.Hash`
    /// @return     if true, the hash was successfully written
    const HashGetFnT = fn (*FileData, [:0]const u8) bool;

    fn InfoGetWin32(self: *FileData, filepath: [:0]const u8) bool {
        if (filepath.len > MAX_PATH_SENTINEL) return false;

        var fd: WIN32_FIND_DATAA = undefined;

        const find_handle = FindFirstFileA(filepath, &fd);
        defer _ = FindClose(find_handle); // TODO: hold onto the handle and reuse instead?
        if (-1 == find_handle) return false;

        self.WriteTime =
            @as(u64, fd.ftLastWriteTime.dwLowDateTime) << 0x0 |
            @as(u64, fd.ftLastWriteTime.dwHighDateTime) << 0x5;
        return true;
    }

    fn HashGetWin32(self: *FileData, filepath: [:0]const u8) bool {
        if (filepath.len > MAX_PATH_SENTINEL) return false;

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

        self.Hash = wh.final();
        return true;
    }
};
