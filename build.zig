const std = @import("std");
const Allocator = std.mem.Allocator;
const SemVer = std.SemanticVersion;
const appinfo = @import("src/patch/appinfo.zig");

// TODO: review overall efficiency/readability
// graph seems slow after rework when adding hashfile
// also seems slower after turning racerlib into module
// TODO: review idiomatic-ness, see: https://ziglang.org/learn/build-system
//  - esp. using addArgs(.{...}) instead of formatting them manually
// TODO: tooling code review
// TODO: get up to date on tooling error and success messaging
// FIXME: need to rethink the DAG and step endpoints
// e.g. endpoints for all the pieces, maximal parallelism, streamline integration of
// hotcopy etc., only running the pieces that need to be for the command and ordered well, etc. ..

// example release build command
// zig build release -Doptimize=ReleaseSafe -Dver="0.0.1" -Dminver="0.0.0" -Drop="F:\Projects\swe1r\annodue\.release"

fn allocFmtSemVer(alloc: Allocator, ver: *const SemVer) ![]u8 {
    if (ver.pre) |pre|
        return try std.fmt.allocPrint(alloc, "{d}.{d}.{d}-{s}", .{ ver.major, ver.minor, ver.patch, pre });

    return try std.fmt.allocPrint(alloc, "{d}.{d}.{d}", .{ ver.major, ver.minor, ver.patch });
}

pub fn build(b: *std.Build) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    // BUILD OPTIONS

    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86,
            .os_tag = .windows,
            .abi = .gnu,
        },
    });

    const optimize = b.standardOptimizeOption(.{
        //.preferred_optimize_mode = .Debug, // NOTE: setting this removes -Doptimize from cli opts
    });

    const DEV_MODE = b.option(bool, "dev", "Enable DEV_MODE") orelse false;

    const BuildMode = enum(u8) { Developer, Release };
    const BUILD_MODE: BuildMode = if (DEV_MODE) .Developer else .Release;

    // MODULES

    const zigini = b.dependency("zigini", .{});
    const zigini_m = zigini.module("ini");
    const zigwin32 = b.dependency("zigwin32", .{});
    const zigwin32_m = zigwin32.module("zigwin32");
    const zzip = b.dependency("zzip", .{});
    const zzip_m = zzip.module("zzip");

    const racerlib = b.createModule(.{
        .source_file = .{ .path = "src/racer/racer.zig" },
    });

    //const appinfo = b.createModule(.{
    //    .source_file = .{ .path = "src/patch/appinfo.zig" },
    //    .dependencies = &.{.{ .name = "zigwin32", .module = zigwin32_m }},
    //});

    const options = b.addOptions();
    const options_label = "BuildOptions";
    options.addOption(BuildMode, "BUILD_MODE", BUILD_MODE);

    // STEP - HOTCOPY

    // TODO: look into only copying files that are actually re-compiled
    // not sure if CopyFileA will just ignore old files anyway tho
    // TODO: look into ObjCopy build system stuff

    const copypath = b.option(
        []const u8,
        "copypath",
        "Path to game directory for hot-reloading in DEV_MODE; will not copy files if not specified",
    ) orelse null;

    const hotcopy_move_files = b.addExecutable(.{
        .name = "hotcopy_move_files",
        .root_source_file = .{ .path = "src/tools/hotcopy_move_files.zig" },
        .target = target,
    });
    hotcopy_move_files.addModule("zigwin32", zigwin32_m);
    hotcopy_move_files.addModule("zzip", zzip_m);

    const hotcopy_move_files_core = b.addRunArtifact(hotcopy_move_files);
    const hotcopy_move_files_plugin = b.addRunArtifact(hotcopy_move_files);
    const hotcopy_move_files_dinput = b.addRunArtifact(hotcopy_move_files);
    if (copypath) |path| {
        const arg_hci = std.fmt.allocPrint(alloc, "-I{s}", .{b.lib_dir}) catch unreachable;

        const arg_hcoc = std.fmt.allocPrint(alloc, "-O{s}/annodue", .{path}) catch unreachable;
        hotcopy_move_files_core.addArg(arg_hci);
        hotcopy_move_files_core.addArg(arg_hcoc);

        const arg_hcop = std.fmt.allocPrint(alloc, "-O{s}/annodue/plugin", .{path}) catch unreachable;
        hotcopy_move_files_plugin.addArg(arg_hci);
        hotcopy_move_files_plugin.addArg(arg_hcop);

        const arg_hcod = std.fmt.allocPrint(alloc, "-O{s}/", .{path}) catch unreachable;
        hotcopy_move_files_dinput.addArg(arg_hci);
        hotcopy_move_files_dinput.addArg(arg_hcod);
    }

    // STEP - PLUGIN HASHING

    const generate_safe_plugin_hash_file = b.addExecutable(.{
        .name = "generate_safe_plugin_hash_file",
        .root_source_file = .{ .path = "src/tools/generate_safe_plugin_hash_file.zig" },
        .target = .{},
    });
    generate_safe_plugin_hash_file.addModule("zigwin32", zigwin32_m);
    generate_safe_plugin_hash_file.addModule("zzip", zzip_m);

    const generate_safe_plugin_hash_file_plugin = b.addRunArtifact(generate_safe_plugin_hash_file);
    const arg_pho_path = std.fmt.allocPrint(alloc, "{s}", .{b.install_path}) catch unreachable;
    const arg_pho_fullpath = std.fmt.allocPrint(alloc, "{s}/hashfile.bin", .{arg_pho_path}) catch unreachable;
    const pho_module_path = b.pathFromRoot(arg_pho_fullpath);
    const arg_pho = std.fmt.allocPrint(alloc, "-O{s}", .{arg_pho_path}) catch unreachable;
    const arg_phi = std.fmt.allocPrint(alloc, "-I{s}", .{b.lib_dir}) catch unreachable;
    generate_safe_plugin_hash_file_plugin.addArg(arg_pho);
    generate_safe_plugin_hash_file_plugin.addArg(arg_phi);

    var hash_step = &generate_safe_plugin_hash_file_plugin.step;

    const hash_plugins_step = b.step(
        "hashfile",
        "Generate valid plugin hashfile",
    );
    hash_plugins_step.dependOn(hash_step);

    // STEP - BUILD DINPUT DLL

    const dinput = b.addSharedLibrary(.{
        .name = "dinput",
        .target = target,
        .optimize = optimize,
    });
    dinput.linkLibC();
    dinput.addCSourceFiles(&.{
        "src/dinput/dinput.c",
    }, &.{});

    var dinput_install = b.addInstallArtifact(dinput, .{});

    const dinput_step = b.step("dinput", "Build dinput.dll");
    dinput_step.dependOn(&dinput_install.step);

    if (DEV_MODE and copypath != null) {
        hotcopy_move_files_dinput.addArg("-Fdinput.dll");
        hotcopy_move_files.step.dependOn(&dinput_install.step);
    }

    // STEP - PACKAGE ZIP FOR RELEASE

    // TODO: update once script is actually written
    // TODO: automate version input somehow?
    // TODO: split dinput part into its own section and integrate with rest
    // of build system; copypath etc.

    const release_zip_files_step = b.step("release", "Package built files for release");

    const releasepath = b.option(
        []const u8,
        "rop",
        "Path to base output directory for release builds; required for 'release' step",
    ) orelse null;

    var zip_step: ?*std.build.Step = null;
    if (releasepath) |rp| {
        const generate_release_zip_files = b.addExecutable(.{
            .name = "generate_release_zip_files",
            .root_source_file = .{ .path = "src/tools/generate_release_zip_files.zig" },
            .target = .{},
        });
        generate_release_zip_files.addModule("zigwin32", zigwin32_m);
        generate_release_zip_files.addModule("zzip", zzip_m);

        const generate_release_zip_files_run = b.addRunArtifact(generate_release_zip_files);

        const arg_z_ip = std.fmt.allocPrint(alloc, "-I {s}/release", .{b.install_path}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_ip);

        const arg_z_dp = std.fmt.allocPrint(alloc, "-D {s}", .{b.lib_dir}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_dp);

        const arg_z_op = std.fmt.allocPrint(alloc, "-O {s}", .{rp}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_op);

        const release_ver = allocFmtSemVer(alloc, &appinfo.VERSION) catch unreachable;
        const arg_z_ver = std.fmt.allocPrint(alloc, "-ver {s}", .{release_ver}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_ver);

        const release_minver = allocFmtSemVer(alloc, &appinfo.VERSION_MIN) catch unreachable;
        const arg_z_minver = std.fmt.allocPrint(alloc, "-minver {s}", .{release_minver}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_minver);

        zip_step = &generate_release_zip_files_run.step;

        const asset_install = b.addInstallDirectory(.{
            .source_dir = .{ .path = "assets" },
            .install_dir = .{ .custom = "release" },
            .install_subdir = "annodue",
        });
        zip_step.?.dependOn(&asset_install.step);
        zip_step.?.dependOn(&dinput_install.step);

        const arg_z_cleanup_path = std.fmt.allocPrint(alloc, "{s}/release", .{b.install_path}) catch unreachable;
        const zip_cleanup = b.addRemoveDirTree(arg_z_cleanup_path);
        zip_cleanup.step.dependOn(zip_step.?);

        release_zip_files_step.dependOn(&zip_cleanup.step);
    }

    // STEP - BUILD PLUGINS

    // TODO: separate build step for test plugin only
    // TODO: reorganize build script to make this more convenient to edit

    var plugin_step = b.step(
        "plugins",
        "Build plugin DLLs",
    );
    hash_step.dependOn(plugin_step);

    // STEP - build collision viewer c/c++ part

    const collision_viewer = b.addStaticLibrary(.{
        .name = "collision_viewer",
        .target = target,
        .optimize = .ReleaseFast,
    });
    collision_viewer.linkLibC();
    collision_viewer.linkLibCpp();
    collision_viewer.addCSourceFiles(&.{
        "src/collision_viewer/main.cpp",
    }, &.{"-std=c++20"});
    collision_viewer.linkSystemLibrary("Dwmapi");
    collision_viewer.linkSystemLibrary("gdi32");

    const PluginDef = struct { name: []const u8, to_hash: bool = true };
    const plugins = [_]PluginDef{
        .{ .name = "test", .to_hash = false },
        .{ .name = "savestate" },
        .{ .name = "qol" },
        .{ .name = "overlay" },
        .{ .name = "gameplaytweak", .to_hash = false },
        .{ .name = "cosmetic" },
        .{ .name = "multiplayer" },
        .{ .name = "developer", .to_hash = false },
        .{ .name = "inputdisplay" },
        .{ .name = "cam7" },
        .{ .name = "collision_viewer" },
    };

    for (plugins) |plugin| {
        const n = std.fmt.allocPrint(alloc, "plugin_{s}", .{plugin.name}) catch continue;
        const p = std.fmt.allocPrint(alloc, "src/patch/dll_{s}.zig", .{plugin.name}) catch continue;
        const dll = b.addSharedLibrary(.{
            .name = n,
            .root_source_file = .{ .path = p },
            .target = target,
            .optimize = optimize,
        });
        dll.linkLibC();
        dll.addOptions(options_label, options);
        dll.addModule("racer", racerlib);
        //dll.addModule("appinfo", appinfo);
        dll.addModule("zigini", zigini_m);
        dll.addModule("zigwin32", zigwin32_m);
        dll.addModule("zzip", zzip_m);
        if (std.mem.eql(u8, plugin.name, "collision_viewer")) {
            dll.linkLibrary(collision_viewer);
            dll.addIncludePath(.{ .path = "src/collision_viewer" });
        }

        // TODO: investigate options arg
        var dll_install = b.addInstallArtifact(dll, .{});
        plugin_step.dependOn(&dll_install.step);

        var bufo = std.fmt.allocPrint(alloc, "-Fplugin_{s}.dll", .{plugin.name}) catch continue;
        if (DEV_MODE and copypath != null)
            hotcopy_move_files_plugin.addArg(bufo);
        if (plugin.to_hash)
            generate_safe_plugin_hash_file_plugin.addArg(bufo);

        var dll_release = b.addInstallArtifact(dll, .{
            .dest_dir = .{ .override = .{ .custom = "release/annodue/plugin" } },
            .pdb_dir = .disabled,
            .implib_dir = .disabled,
        });
        if (plugin.to_hash and zip_step != null) zip_step.?.dependOn(&dll_release.step);
    }

    // STEP - BUILD MAIN DLL

    const core = b.addSharedLibrary(.{
        .name = "annodue",
        .root_source_file = .{ .path = "src/patch/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    core.linkLibC();
    core.addOptions(options_label, options);
    core.addModule("racer", racerlib);
    //core.addModule("appinfo", appinfo);
    core.addModule("zigini", zigini_m);
    core.addModule("zigwin32", zigwin32_m);
    core.addModule("zzip", zzip_m);
    core.addAnonymousModule("hashfile", .{ .source_file = .{ .path = pho_module_path } });
    // TODO: don't make the core depend on plugin_step,
    // connect plugins to default_step so it can be parallel unless doing release build
    core.step.dependOn(
        // we skip runtime hash checks in dev builds
        if (DEV_MODE) plugin_step else hash_step,
    );

    // TODO: investigate options arg
    const core_install = b.addInstallArtifact(core, .{});

    if (DEV_MODE and copypath != null) {
        hotcopy_move_files_core.addArg("-Fannodue.dll");
        hotcopy_move_files.step.dependOn(&core_install.step);
    }

    var core_release = b.addInstallArtifact(core, .{
        .dest_dir = .{ .override = .{ .custom = "release/annodue" } },
        .pdb_dir = .disabled,
        .implib_dir = .disabled,
    });
    if (zip_step != null) zip_step.?.dependOn(&core_release.step);

    // DEFAULT STEP

    // TODO: make plugins connect here instead of core step
    b.default_step.dependOn(&core_install.step);
    b.default_step.dependOn(&dinput_install.step);
    if (DEV_MODE and copypath != null) {
        b.default_step.dependOn(&hotcopy_move_files_core.step);
        b.default_step.dependOn(&hotcopy_move_files_plugin.step);
        b.default_step.dependOn(&hotcopy_move_files_dinput.step);
    }

    // MISC OLD STUFF

    //// Creates a step for unit testing. This only builds the test executable
    //// but does not run it.
    //const main_tests = b.addTest(.{
    //    .root_source_file = .{ .path = "src/main.zig" },
    //    .target = target,
    //    .optimize = optimize,
    //});
    //
    //const run_main_tests = b.addRunArtifact(main_tests);
    //
    //// This creates a build step. It will be visible in the `zig build --help` menu,
    //// and can be selected like this: `zig build test`
    //// This will evaluate the `test` step rather than the default, which is "install".
    //const test_step = b.step("test", "Run library tests");
    //test_step.dependOn(&run_main_tests.step);
}
