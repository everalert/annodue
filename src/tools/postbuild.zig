const std = @import("std");

const w = std.os.windows;
const w32 = @import("zigwin32");
const w32ll = w32.system.library_loader;
const w32f = w32.foundation;
const w32fs = w32.storage.file_system;

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

    if (0 == w32fs.CreateDirectoryA(o_path.?, null)) {
        var e = w.kernel32.GetLastError();
        if (e == w.Win32Error.PATH_NOT_FOUND) {
            std.debug.print(
                "ERROR  Cannot create directory \"{s}\"; intermediary path does not exist.\n",
                .{o_path.?},
            );
            return error.InvalidOutputDirectory;
        }
    }

    var copy_all: bool = true;
    var copy_partial: bool = false;
    var buf1: [1023:0]u8 = undefined;
    var buf2: [1023:0]u8 = undefined;
    for (files.items) |f| {
        var i = try std.fmt.bufPrintZ(&buf1, "{s}/{s}", .{ i_path.?, f });
        var o = try std.fmt.bufPrintZ(&buf2, "{s}/{s}", .{ o_path.?, f });
        if (0 == w32fs.CopyFileA(i, o, 0)) {
            var e = w.kernel32.GetLastError();
            std.debug.print("ERROR  {s}  {s}\n", .{ @tagName(e), f });
            copy_all = false;
        } else copy_partial = true;
    }

    if (!copy_partial) {
        std.debug.print("ERROR  No files copied to {s}\n", .{o_path.?});
        //return error.CopyFileFailure;
    } else if (!copy_all) {
        std.debug.print("ERROR  Some files not copied to {s}\n", .{o_path.?});
        //return error.PartialCopyFileFailure;
    } else std.debug.print("SUCCESS  {s}\n", .{o_path.?});
}
