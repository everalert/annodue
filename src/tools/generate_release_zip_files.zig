const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const SemVer = std.SemanticVersion;
const Dir = std.fs.Dir;
const Crc32 = std.hash.Crc32;
const assert = std.debug.assert;

const zzip = @import("zzip");
const Zip = zzip.ZipArchive.Zip;
const File = zzip.ZipFile.File;
const ExtraField = zzip.ExtraField.ExtraField;
const ExtendedTimestampEF = zzip.ExtraField.ExtendedTimestampEF;

const usage =
    \\CLI Arguments:
    \\  -ver <SemVer>
    \\  -minver <SemVer>
    \\  -I <src_dir>
    \\  -O <out_dir>        will write files to "<out_dir>/<SemVer>/*" if specified
    \\  -D <dinput_path>    excluding "/dinput.dll"
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var alloc = arena.allocator();
    arena.deinit();

    // parse args

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    var ver: ?[]const u8 = null;
    var ver_sv: SemVer = undefined;
    var minver: ?[]const u8 = null;
    var minver_sv: SemVer = undefined;
    var dinput: ?[]const u8 = null;
    var i_path: ?[]const u8 = null;
    var o_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-ver")) {
            ver_sv = SemVer.parse(arg[5..]) catch continue;
            ver = @constCast(arg[5..]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-minver")) {
            minver_sv = SemVer.parse(arg[8..]) catch continue;
            minver = @constCast(arg[8..]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-I")) {
            i_path = @constCast(arg[3..]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-O")) {
            o_path = @constCast(arg[3..]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-D") and !std.mem.endsWith(u8, arg, "dinput.dll")) {
            dinput = @constCast(arg[3..]);
            continue;
        }
    }

    if (i_path == null) return error.NoInputPath;
    if (ver == null) return error.NoVersionSpecified;
    if (minver != null and SemVer.order(minver_sv, ver_sv) != .lt) return error.MinimumVersionNotSmaller;

    // generate the zip archive

    // FIXME: (ZZIP) impl zip unpacking changes (slash correction) into zzip lib
    // FIXME: (ZZIP) impl a decent canned way of doing this into zzip lib

    const cwd = std.fs.cwd();

    var z = Zip.init(alloc);
    defer z.deinit();
    var z_up = Zip.init(alloc);
    defer z_up.deinit();

    var base_dir = try cwd.openIterableDir(i_path.?, .{});
    defer base_dir.close();
    var walker = try base_dir.walk(alloc);
    defer walker.deinit();

    // TODO: assign update tag to appropriate files in future versions
    var dinput_exists: bool = dinput != null;
    var minver_exists: bool = minver != null;
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        if (dinput_exists and std.mem.eql(u8, entry.path, "dinput.dll")) {
            dinput_exists = false;
            if (dinput != null) continue;
        }
        if (minver_exists and std.mem.eql(u8, entry.path, "minver.txt")) {
            minver_exists = false;
            if (minver != null) continue;
        }

        const path = try std.fmt.allocPrint(alloc, "{s}", .{entry.path}); // lifetime
        if (builtin.os.tag == .windows) { // FIXME: remove hack, fix zzip instead
            for (0..path.len) |i| {
                if (path[i] == '\\') path[i] = '/';
            }
        }

        try appendFileToFile(alloc, &z, &base_dir.dir, path);

        if (std.mem.startsWith(u8, path, "annodue/"))
            try appendFileToFile(alloc, &z_up, &base_dir.dir, path);
    }

    // TODO: might need to include dinput.dll in future update zips too
    if (dinput_exists and dinput != null) {
        var dir = try cwd.openDir(dinput.?, .{});
        defer dir.close();
        try appendFileToFile(alloc, &z, &dir, "dinput.dll");
    } else {
        std.debug.print("[ZIP] WARNING: '-D' missing, dinput.dll assumed to already be in input path\n", .{});
    }

    // TODO: also add readme.txt to non-update zip?
    if (minver_exists and minver != null) {
        const data = try std.fmt.allocPrint(
            alloc,
            "{s}\nhttps://api.github.com/repos/everalert/annodue/releases/tags/{s}",
            .{ minver.?, minver.? },
        );
        try appendDataToFile(alloc, &z_up, data, "minver.txt");
    } else {
        std.debug.print("[ZIP] WARNING: '-minver' missing or invalid, minver.txt will not be generated\n", .{});
    }

    const readme_data = try std.fmt.allocPrint(alloc, "To install, unzip the contents of this archive to the game directory.\n\nFor more information, go to https://github.com/everalert/annodue/tree/{s}", .{ver.?});
    try appendDataToFile(alloc, &z, readme_data, "readme.txt");

    // write the output to disk

    if (o_path == null)
        std.debug.print("[ZIP] WARNING: '-O' missing, writing output to current directory\n", .{});

    const o_fullpath = if (o_path) |p| try std.fmt.allocPrint(alloc, "{s}/{s}", .{ p, ver.? }) else "";
    var o_dir = try cwd.makeOpenPath(o_fullpath, .{});
    defer o_dir.close();

    var archive = ArrayList(u8).init(alloc);
    defer archive.deinit();
    try z.write(&archive, null);

    const o_filename = try std.fmt.allocPrint(alloc, "annodue-{s}.zip", .{ver.?});
    const out = try o_dir.createFile(o_filename, .{});
    defer out.close();
    try out.writeAll(archive.items);

    var archive_up = ArrayList(u8).init(alloc);
    defer archive_up.deinit();
    try z_up.write(&archive_up, null);

    const o_filename_up = try std.fmt.allocPrint(alloc, "annodue-{s}-update.zip", .{ver.?});
    const out_up = try o_dir.createFile(o_filename_up, .{});
    defer out_up.close();
    try out_up.writeAll(archive_up.items);

    const out_crc32 = try o_dir.createFile("CRC32.txt", .{});
    defer out_crc32.close();
    const crc_row_fmt = "{X}\t{s: <24}\n";
    _ = try out_crc32.write(try std.fmt.allocPrint(alloc, crc_row_fmt, .{
        Crc32.hash(archive.items),
        o_filename,
    }));
    _ = try out_crc32.write(try std.fmt.allocPrint(alloc, crc_row_fmt, .{
        Crc32.hash(archive_up.items),
        o_filename_up,
    }));
}

fn appendFileToFile(alloc: Allocator, z: *Zip, dir: *const Dir, path: []const u8) !void {
    const file = try dir.openFile(path, .{});
    defer file.close();
    const raw_data = try file.readToEndAlloc(alloc, 1 << 31);
    var zipfile = try makeZipFile(alloc, raw_data, path);
    //var zipfile = try File.init(alloc, path, path); // instead of all of above

    var ets = try alloc.create(ExtendedTimestampEF);
    try ets.updateFromFile(&file, false);
    try zipfile.extra_fields.append(ets.extraField());
    try z.files.append(zipfile);
}

fn appendDataToFile(alloc: Allocator, z: *Zip, data: []const u8, path: []const u8) !void {
    var zipfile = try makeZipFile(alloc, data, path);
    try z.files.append(zipfile);
}

fn makeZipFile(alloc: Allocator, data: []const u8, path: []const u8) !File {
    return .{
        .allocator = alloc,
        .ver_made_by = .{ .spec = .@"2.0" },
        .ver_min = .{ .spec = .@"2.0" },
        .crc32 = Crc32.hash(data),
        .filename = path,
        .raw_data = data,
        .extra_fields = ArrayList(ExtraField).init(alloc),
        .compression = .Deflate,
    };
}
