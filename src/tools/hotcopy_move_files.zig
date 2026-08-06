const std = @import("std");

const w32 = @import("zigwin32");
const GetLastError = w32.foundation.GetLastError;
const CreateDirectoryA = w32.storage.file_system.CreateDirectoryA;
const CopyFileA = w32.storage.file_system.CopyFileA;
const PATH_NOT_FOUND = w32.foundation.ERROR_PATH_NOT_FOUND;

// TODO: cleanup so that it doesn't have to be called a separate time for each subdir

const usage =
    \\CLI Arguments:
    \\  -Isrc_dir
    \\  -Odest_dir
    \\  -Ffile [repeatable]
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    var i_path: ?[:0]u8 = null;
    var o_path: ?[:0]u8 = null;
    var files = std.ArrayList([:0]u8).init(alloc);
    defer files.deinit();

    while (args.next()) |a| {
        if (a.len > 2 and std.mem.eql(u8, "-I", a[0..2]))
            i_path = @constCast(a[2..]);
        if (a.len > 2 and std.mem.eql(u8, "-O", a[0..2]))
            o_path = @constCast(a[2..]);
        if (a.len > 2 and std.mem.eql(u8, "-F", a[0..2]))
            try files.append(@constCast(a[2..]));
    }

    if (i_path == null) return error.NoInputPath;
    if (o_path == null) return error.NoOutputPath;

    if (0 == CreateDirectoryA(o_path.?, null)) {
        var e = GetLastError();
        if (e == PATH_NOT_FOUND) {
            std.debug.print(
                "MOVE ERROR  Cannot create directory \"{s}\"; intermediary path does not exist.\n",
                .{o_path.?},
            );
            return error.InvalidOutputDirectory;
        }
    }

    //std.debug.print("\n", .{});

    var copy_all: bool = true;
    var copy_partial: bool = false;
    var buf1: [1023:0]u8 = undefined;
    var buf2: [1023:0]u8 = undefined;
    for (files.items) |f| {
        var i = try std.fmt.bufPrintZ(&buf1, "{s}/{s}", .{ i_path.?, f });
        var o = try std.fmt.bufPrintZ(&buf2, "{s}/{s}", .{ o_path.?, f });
        if (0 == CopyFileA(i, o, 0)) {
            var e = GetLastError();
            std.debug.print("MOVE ERROR  {s}  {s}\n", .{ @tagName(e), f });
            copy_all = false;
        } else copy_partial = true;
    }

    if (!copy_partial) {
        std.debug.print("MOVE ERROR  No files copied to {s}\n", .{o_path.?});
        //return error.CopyFileFailure;
    } else if (!copy_all) {
        std.debug.print("MOVE ERROR  Some files not copied to {s}\n", .{o_path.?});
        //return error.PartialCopyFileFailure;
    } else std.debug.print("MOVE SUCCESS  {s}\n", .{o_path.?});

    //std.debug.print("\n", .{});
}
