const std = @import("std");

// TODO: look into getting rid of zigini from git once and for all!!1
// TODO: review overall efficiency/readability, graph seems slow after rework when adding hashfile
// TODO: review idiomatic-ness, see: https://ziglang.org/learn/build-system
//  - esp. using addArgs(.{...}) instead of formatting them manually
// TODO: tooling code review
// TODO: get up to date on tooling error and success messaging

// example release build command
// zig build release -Doptimize=ReleaseSafe -Dver="0.0.1" -Dminver="0.0.0"

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

    //const zigini = b.dependency("zigini", .{});
    //const zigini_m = zigini.module("zigini");
    const zigwin32 = b.dependency("zigwin32", .{});
    const zigwin32_m = zigwin32.module("zigwin32");
    const zzip = b.dependency("zzip", .{});
    const zzip_m = zzip.module("zzip");

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
    if (copypath) |path| {
        const arg_hci = std.fmt.allocPrint(alloc, "-I{s}", .{b.lib_dir}) catch unreachable;

        const arg_hcoc = std.fmt.allocPrint(alloc, "-O{s}", .{path}) catch unreachable;
        hotcopy_move_files_core.addArg(arg_hci);
        hotcopy_move_files_core.addArg(arg_hcoc);

        const arg_hcop = std.fmt.allocPrint(alloc, "-O{s}/plugin", .{path}) catch unreachable;
        hotcopy_move_files_plugin.addArg(arg_hci);
        hotcopy_move_files_plugin.addArg(arg_hcop);
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

    // STEP - PACKAGE ZIP FOR RELEASE

    // TODO: update once script is actually written
    // TODO: automate version input somehow?

    const dinput_dll = b.addSharedLibrary(.{
        .name = "dinput",
        .target = target,
        .optimize = optimize,
    });
    dinput_dll.linkLibC();
    dinput_dll.addCSourceFiles(&.{
        "src/dinput/dinput.c",
    }, &.{});

    var dinput_dll_release = b.addInstallArtifact(dinput_dll, .{
        .dest_dir = .{ .override = .{ .custom = "release" } },
        .pdb_dir = .disabled,
        .implib_dir = .disabled,
    });

    // NOTE: minver checks fail if not specified
    const release_ver = b.option([]const u8, "ver", "release version") orelse "0.0.0";
    const release_minver = b.option([]const u8, "minver", "minimum version needed to auto-update to this release") orelse release_ver;

    const generate_release_zip_files = b.addExecutable(.{
        .name = "generate_release_zip_files",
        .root_source_file = .{ .path = "src/tools/generate_release_zip_files.zig" },
        .target = .{},
    });
    generate_release_zip_files.addModule("zigwin32", zigwin32_m);
    generate_release_zip_files.addModule("zzip", zzip_m);

    const generate_release_zip_files_run = b.addRunArtifact(generate_release_zip_files);
    {
        const arg_z_ip = std.fmt.allocPrint(alloc, "-I {s}/release", .{b.install_path}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_ip);

        const arg_z_dp = std.fmt.allocPrint(alloc, "-D{s}", .{dinput_dll.out_filename}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_dp);

        const arg_z_op_path = b.build_root.handle.realpathAlloc(alloc, "./.release") catch unreachable;
        const arg_z_op = std.fmt.allocPrint(alloc, "-O {s}", .{arg_z_op_path}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_op);

        const arg_z_ver = std.fmt.allocPrint(alloc, "-ver {s}", .{release_ver}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_ver);

        const arg_z_minver = std.fmt.allocPrint(alloc, "-minver {s}", .{release_minver}) catch unreachable;
        generate_release_zip_files_run.addArg(arg_z_minver);
    }

    var zip_step = &generate_release_zip_files_run.step;

    const asset_install = b.addInstallDirectory(.{
        .source_dir = .{ .path = "assets" },
        .install_dir = .{ .custom = "release" },
        .install_subdir = "annodue",
    });
    zip_step.dependOn(&asset_install.step);
    zip_step.dependOn(&dinput_dll_release.step);

    const arg_z_cleanup_path = std.fmt.allocPrint(alloc, "{s}/release", .{b.install_path}) catch unreachable;
    const zip_cleanup = b.addRemoveDirTree(arg_z_cleanup_path);
    zip_cleanup.step.dependOn(zip_step);

    const release_zip_files_step = b.step("release", "Package built files for release");
    release_zip_files_step.dependOn(&zip_cleanup.step);

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
        "src/collision_viewer/imgui-d3d3/imgui.cpp",
        "src/collision_viewer/imgui-d3d3/imgui_draw.cpp",
        "src/collision_viewer/imgui-d3d3/imgui_tables.cpp",
        "src/collision_viewer/imgui-d3d3/imgui_widgets.cpp",
        "src/collision_viewer/imgui-d3d3/backends/imgui_impl_d3d.cpp",
        "src/collision_viewer/imgui-d3d3/backends/imgui_impl_win32.cpp",
        "src/collision_viewer/detours-master/src/detours.cpp",
        "src/collision_viewer/detours-master/src/modules.cpp",
        "src/collision_viewer/detours-master/src/disasm.cpp",
        "src/collision_viewer/detours-master/src/image.cpp",
        "src/collision_viewer/detours-master/src/creatwth.cpp",
        "src/collision_viewer/detours-master/src/disolx86.cpp",
    }, &.{"-std=c++20"});
    collision_viewer.addIncludePath(.{ .path = "src/collision_viewer/imgui-d3d3/" });
    collision_viewer.addIncludePath(.{ .path = "src/collision_viewer/detours-master/include" });
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
        dll.addModule("zigwin32", zigwin32_m);
        dll.addModule("zzip", zzip_m);
        if (std.mem.eql(u8, plugin.name, "collision_viewer"))
            dll.linkLibrary(collision_viewer);

        // TODO: investigate options arg
        var dll_install = b.addInstallArtifact(dll, .{});
        plugin_step.dependOn(&dll_install.step);

        var bufo = std.fmt.allocPrint(alloc, "-Fplugin_{s}.dll", .{plugin.name}) catch continue;
        hotcopy_move_files_plugin.addArg(bufo);
        if (plugin.to_hash) generate_safe_plugin_hash_file_plugin.addArg(bufo);

        var dll_release = b.addInstallArtifact(dll, .{
            .dest_dir = .{ .override = .{ .custom = "release/annodue/plugin" } },
            .pdb_dir = .disabled,
            .implib_dir = .disabled,
        });
        if (plugin.to_hash) zip_step.dependOn(&dll_release.step);
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
    core.addModule("zigwin32", zigwin32_m);
    core.addModule("zzip", zzip_m);
    core.addAnonymousModule("hashfile", .{ .source_file = .{ .path = pho_module_path } });
    core.step.dependOn(
        // we skip runtime hash checks in dev builds
        if (DEV_MODE) plugin_step else hash_step,
    );

    // TODO: investigate options arg
    const core_install = b.addInstallArtifact(core, .{});

    hotcopy_move_files_core.addArg("-Fannodue.dll");
    hotcopy_move_files.step.dependOn(&core_install.step);

    var core_release = b.addInstallArtifact(core, .{
        .dest_dir = .{ .override = .{ .custom = "release/annodue" } },
        .pdb_dir = .disabled,
        .implib_dir = .disabled,
    });
    zip_step.dependOn(&core_release.step);

    // DEFAULT STEP

    b.default_step.dependOn(&core_install.step);
    if (DEV_MODE and copypath != null) {
        b.default_step.dependOn(&hotcopy_move_files_core.step);
        b.default_step.dependOn(&hotcopy_move_files_plugin.step);
    }

    // MISC OLD STUFF

    //    // Creates a step for unit testing. This only builds the test executable
    //    // but does not run it.
    //    const main_tests = b.addTest(.{
    //        .root_source_file = .{ .path = "src/main.zig" },
    //        .target = target,
    //        .optimize = optimize,
    //    });
    //
    //    const run_main_tests = b.addRunArtifact(main_tests);
    //
    //    // This creates a build step. It will be visible in the `zig build --help` menu,
    //    // and can be selected like this: `zig build test`
    //    // This will evaluate the `test` step rather than the default, which is "install".
    //    const test_step = b.step("test", "Run library tests");
    //    test_step.dependOn(&run_main_tests.step);
}
