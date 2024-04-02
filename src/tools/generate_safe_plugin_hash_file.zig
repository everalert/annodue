const std = @import("std");

const Sha512 = std.crypto.hash.sha2.Sha512;

const w = std.os.windows;
const w32 = @import("zigwin32");
const w32ll = w32.system.library_loader;
const w32f = w32.foundation;
const w32fs = w32.storage.file_system;

// TODO: add output param
// TODO: remove length from format
// TODO: add hash of the hashes at the end
// TODO: include filename in hashing

// Generates 'plugin_hash.bin' to be included in annodue.dll via @embedFile

// CLI Arguments:
//   -Isrc_dir
//   -Odest_dir
//   -Ffile     [repeatable]

// Output File Format
// u32          number of hashes in array
// [_][64]u8    sorted array of sha512 hashes

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // parse args

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    var i_path: ?[:0]u8 = null;
    var o_path: ?[:0]u8 = null;
    var files = std.ArrayList([]u8).init(alloc);
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
                "MOVE ERROR  Cannot create directory \"{s}\"; intermediary path does not exist.\n",
                .{o_path.?},
            );
            return error.InvalidOutputDirectory;
        }
    }

    // generate hash file

    //std.debug.print("\n", .{});
    //std.debug.print("Generating: plugin_hash.bin... ", .{});

    const hash_filename = try std.fmt.allocPrint(alloc, "{s}/hashfile.bin", .{o_path.?});
    const hash_file = try std.fs.cwd().createFile(hash_filename, .{});
    defer hash_file.close();

    _ = try hash_file.write(@as([*]u8, @ptrCast(&files.items.len))[0..4]);

    var hashes = std.ArrayList([64]u8).init(alloc);
    for (files.items) |f| {
        const dll_filename = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ i_path.?, f });
        const digest = try getFileSha512(dll_filename);
        try hashes.append(digest);
    }

    std.mem.sort([64]u8, hashes.items, {}, lessThanFnHash);
    for (hashes.items) |h|
        _ = try hash_file.write(&h);

    std.debug.print("GENERATE HASHFILE SUCCESS\n", .{});
    //std.debug.print("\n", .{});
}

// helpers

fn getFileSha512(filename: []u8) ![Sha512.digest_length]u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var sha512 = Sha512.init(.{});
    const rdr = file.reader();

    var buf: [std.mem.page_size]u8 = undefined;
    var n = try rdr.read(&buf);
    while (n != 0) {
        sha512.update(buf[0..n]);
        n = try rdr.read(&buf);
    }

    return sha512.finalResult();
}

fn lessThanFnHash(_: void, a: [64]u8, b: [64]u8) bool {
    for (a, b) |a_v, b_v| {
        if (a_v == b_v) continue;
        return a_v < b_v;
    }
    return false;
}
