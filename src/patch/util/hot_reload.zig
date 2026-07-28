const std = @import("std");

const assert = std.debug.assert;
const panic = std.debug.panic;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const w32 = @import("zigwin32");
const FILETIME = w32.foundation.FILETIME;
const MAX_PATH = w32.foundation.MAX_PATH;
const MAX_PATH_SENTINEL = MAX_PATH - 1;
const WIN32_FIND_DATAA = w32.storage.file_system.WIN32_FIND_DATAA;
const FindFirstFileA = w32.storage.file_system.FindFirstFileA;
const FindClose = w32.storage.file_system.FindClose;

// FIXME: todos before moving back to finalize font stuff..
//  - if it seems easy, impl the different versions (at least the single-file ver)
//  - add tests
//  - add docs (particularly top-level docs comment summary)
//  - probably also abstract out Plugins from Hook and clean up that API
//  - review fixme/todos across whole file and tie up any loose ends/documentation
//  - after finalizing, don't forget to actually try using this for fonts lol

// TODO: version which monitors a whole directory, and can handle cases such as
//  new files, file deletion, etc. to dynamically adapt the hot reload list, rather
//  than making a list and querying the files individually
//      see: ReadDirectoryChangesW/-ExW
// TODO: version which takes an allocator (and uses a hashmap)? avoided this before
//  because my use case didn't need much memory, but might be worth keeping in mind

// FIXME: seems to reload twice when compiling DLLs; maybe the file size and
//  modification time update at different times?
// FIXME: currently this doesn't protect against duplicate file listings
// TODO: ?? impl "skip next load" (like ASettings) as part of hot-reloader
// TODO: ?? manage tracked files via handles
// TODO: ?? add unload callback, might make things easier to reason about on impl
//  side; will need to be called on deinit and in the various Untrack fns
// TODO: ?? add filename (not filepath) to FileRecord, so that user can easily
//  get it without searching the filepath string?
// TODO: ?? add load time to FileRecord? to differentiate between file checking
//  and file successfully loading
// TODO: ?? impl the following
//  pub fn TrackDirectory() void {} // batch add files from directory; needs some method to filter files
//  pub fn UntrackDirectory() void {}
//  pub fn UntrackAll() void {}

/// file hot reload management util
///  - "statically" allocated memory; for single-file usage, pass in ITEM_MAX=1
/// @ContextHandleT     reference to data associated with the file being tracked,
///                     typically a struct pointer but may be an opaque handle
///                     such as an array index, or void to "pass" on context
/// @ITEM_MAX           max number of trackable items, statically allocated
pub fn HotReload(comptime ContextHandleT: type, comptime ITEM_MAX: usize) type {
    return struct {
        const HotReloadT = @This();

        FileList: [ITEM_MAX]FileRecord = undefined,
        FileListUsed: [ITEM_MAX]bool = std.mem.zeroes([ITEM_MAX]bool),
        FileListCount: usize = 0,

        // TODO: ?? return an enum for more result state granularity?
        /// callback for loading the hot-reload target. this will run both when
        /// loading the target initially and when hot-reloading, and therefore
        /// will also need to handle unloading if necessary
        /// @return     true if load successful
        fnLoad: LoadCallback,
        fnLoadResult: ?LoadResultCallback = null,

        CheckDelay: usize = 0,
        CheckTimestamp: usize = 0,
        CheckIndex: usize = 0,

        const LoadResultT = bool;
        const LoadCallback = *const fn (ctx: ContextHandleT, filepath: [*:0]const u8) LoadResultT;
        const LoadResultCallback = *const fn (ctx: ContextHandleT, filepath: [*:0]const u8, result: LoadResultT) void;

        pub fn Init(fn_load: LoadCallback) HotReloadT {
            return HotReloadT{
                .fnLoad = fn_load,
            };
        }

        pub fn Deinit(_: *HotReloadT) void {
            //self.FileList.deinit();
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

            const result = self.fnLoad(item.Context, &item.FilePath);
            if (self.fnLoadResult) |f| f(item.Context, &item.FilePath, result);
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
            const result = self.fnLoad(ctx, filepath);
            if (self.fnLoadResult) |f| f(ctx, filepath, result);

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
            const result = self.fnLoad(ctx, filepath);
            if (self.fnLoadResult) |f| f(ctx, filepath, result);
        }

        // TODO: ?? also call fnUnload here (after implementing such)
        // TODO: do something about possible duplicates. not sure if they should
        //  be prevented from the jump, or if that should be an option
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

        pub const FileRecord = struct {
            Context: ContextHandleT,
            FilePath: [MAX_PATH_SENTINEL:0]u8,
            FileSizeLow: u32 = 0,
            FileSizeHigh: u32 = 0,
            WriteTimeLow: u32 = 0,
            WriteTimeHigh: u32 = 0,

            const FileRecordError = error{ DataGetFailed, FileNameTooLong };

            /// will always clear and initialize the record. if the file is not
            /// readable, the time/size info will be cleared to 0
            /// @return     whether the file was actually readable
            pub fn Init(record: *FileRecord, filepath: [*:0]const u8, ctx: ContextHandleT) bool {
                record.* = std.mem.zeroes(FileRecord);
                _ = std.fmt.bufPrintZ(&record.FilePath, "{s}", .{filepath}) catch unreachable;
                record.Context = ctx;

                var fd: WIN32_FIND_DATAA = undefined;
                if (!DataGet(filepath, &fd)) return false;

                record.DataWrite(&fd);
                return true;
            }

            /// checks the file and updates the record if needed
            /// @return     whether or not the file appears to have changed
            pub fn Check(self: *FileRecord) bool {
                var fd: WIN32_FIND_DATAA = undefined;
                if (!DataGet(&self.FilePath, &fd)) return false;

                if (self.WriteTimeLow == fd.ftLastWriteTime.dwLowDateTime and
                    self.FileSizeLow == fd.nFileSizeLow and
                    self.WriteTimeHigh == fd.ftLastWriteTime.dwHighDateTime and
                    self.FileSizeHigh == fd.nFileSizeHigh)
                    return false;

                DataWrite(self, &fd);
                return true;
            }

            pub fn DataWrite(self: *FileRecord, fd: *const WIN32_FIND_DATAA) void {
                self.WriteTimeLow = fd.ftLastWriteTime.dwLowDateTime;
                self.WriteTimeHigh = fd.ftLastWriteTime.dwHighDateTime;
                self.FileSizeLow = fd.nFileSizeLow;
                self.FileSizeHigh = fd.nFileSizeHigh;
            }

            pub fn DataGet(filepath: [*:0]const u8, fd: *WIN32_FIND_DATAA) bool {
                if (std.mem.len(filepath) > MAX_PATH_SENTINEL) return false;

                const find_handle = FindFirstFileA(filepath, fd);
                defer _ = FindClose(find_handle); // TODO: hold onto the handle and reuse instead?
                return (-1 != find_handle);
            }
        };
    };
}
