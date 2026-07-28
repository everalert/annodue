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
//  - review and impl the below todo/fixme as appropriate
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
// TODO: simplified version which operates on a single file only, as a convenience
//  for sites like ASettings that only ever track one file
// TODO: version which works with static memory, and takes a buffer or otherwise
//  assumes the allocator given to it will have enough memory to handle the tracklist size

// FIXME: currently this doesn't protect against duplicate file listings
// TODO: ?? impl "skip next load" (like ASettings) as part of hot-reloader
// TODO: ?? callback for post-load action to handle different success states
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
        // TODO: or don't return null at all? seems like it was only used to
        //  handle load check error cases anyway, which are covered before ever
        //  calling this callback under hot_reload
        // TODO: or return an enum that can be fed into result callback a little
        //  more nicely
        /// callback for loading the hot-reload target. this will run both when
        /// loading the target initially, and when hot-reloading
        /// @return     null  = load aborted
        ///             true  = load successful
        ///             false = load failure
        fnLoad: LoadCallback = undefined,
        fnLoadResult: ?LoadResultCallback = null,

        const LoadCallback = *const fn (ctx: ContextHandleT, filepath: [*:0]const u8) ?bool;
        const LoadResultCallback = *const fn (ctx: ContextHandleT, filepath: [*:0]const u8, result: ?bool) void;

        pub fn Init(gpa: Allocator, fn_load: LoadCallback) HotReloadT {
            return HotReloadT{
                .FileList = ArrayList(FileRecord).init(gpa),
                .fnLoad = fn_load,
            };
        }

        pub fn Deinit(self: *HotReloadT) void {
            self.FileList.deinit();
        }

        pub fn Update(self: *HotReloadT, timestamp: u32) void {
            if (self.FileList.items.len == 0) return;
            if (timestamp < self.CheckTimestamp + self.CheckDelay) return;

            const item = &self.FileList.items[self.CheckIndex];
            if (!item.Check()) return;

            const load = self.fnLoad(item.Context, &item.FilePath);

            if (self.fnLoadResult) |f|
                f(item.Context, &item.FilePath, load);

            self.CheckIndex = (self.CheckIndex + 1) % self.FileList.items.len;
            self.CheckTimestamp = timestamp;
        }

        /// adds a file to track for hot reloading, and runs the load-related
        /// callbacks. if the loading process fails for any reason, the file will
        /// be removed from the tracking list automatically.
        /// @return     true when the callbacks successfully run; on false, any
        ///             failure case dependent on `fnLoadResult` will not be
        ///             handled, so the caller may need to do manual cleanup
        pub fn TrackFile(self: *HotReloadT, filepath: [*:0]const u8, ctx: ContextHandleT) bool {
            var queue_cleanup: bool = true;
            defer _ = if (queue_cleanup) self.FileList.pop();

            if (self.FileList.items.len == self.FileList.capacity) {
                const new_capacity = self.FileList.capacity + 1;
                self.FileList.ensureTotalCapacity(new_capacity) catch
                    self.FileList.ensureTotalCapacityPrecise(new_capacity) catch
                    return false;
            }

            var record: *FileRecord = self.FileList.addOneAssumeCapacity();
            if (!record.Init(filepath, ctx)) return false;
            queue_cleanup = false;

            const result = self.fnLoad(ctx, filepath);

            if (self.fnLoadResult) |f|
                f(ctx, filepath, result);

            return true;
        }

        /// adds a file to track for hot reloading, and runs the load-related
        /// callbacks on it if possible. the file will always be added to the
        /// tracking list, even if the file doesn't exist yet
        pub fn TrackFileAlways(self: *HotReloadT, filepath: [*:0]const u8, ctx: ContextHandleT) void {
            if (self.FileList.items.len == self.FileList.capacity) {
                const new_capacity = self.FileList.capacity + 1;
                self.FileList.ensureTotalCapacity(new_capacity) catch
                    self.FileList.ensureTotalCapacityPrecise(new_capacity) catch |e|
                    panic("TrackFileAlways: {s}", .{@errorName(e)});
            }

            var record: *FileRecord = self.FileList.addOneAssumeCapacity();
            if (!record.Init(filepath, ctx)) return;

            const result = self.fnLoad(ctx, filepath);

            if (self.fnLoadResult) |f|
                f(ctx, filepath, result);
        }

        // TODO: do something about possible duplicates. not sure if they should
        //  be prevented from the jump, or if that should be an option
        // FIXME: more stable CheckIndex that doesn't move around so much if it
        //  doesn't need to
        // FIXME: not sure why this uses swapRemove, but a freelist was needed
        //  for the plugin contexts even though the lists are the same size; should
        //  this just be a freelist, until proven that unbounded file tracking is
        //  required somewhere?
        pub fn UntrackFile(self: *HotReloadT, filepath: [*:0]const u8) void {
            for (0..self.FileList.items.len) |i| {
                if (std.mem.orderZ(u8, filepath, &self.FileList.items[i].FilePath) == .eq) {
                    _ = self.FileList.swapRemove(i);
                    self.CheckIndex %= self.FileList.items.len;
                    break;
                }
            }
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
