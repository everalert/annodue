const std = @import("std");

// TODO: review overall efficiency/readability

pub fn build(b: *std.Build) void {
    var buf1: [1024]u8 = undefined;
    var buf2: [1024]u8 = undefined;

    // BUILD OPTIONS

    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86,
            .os_tag = .windows,
            .abi = .gnu,
        },
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

    // MODULES

    //const zigini = b.dependency("zigini", .{});
    //const zigini_m = zigini.module("zigini");
    const zigwin32 = b.dependency("zigwin32", .{});
    const zigwin32_m = zigwin32.module("zigwin32");

    // STEP - HOTCOPY

    // FIXME: kinda slow, comparable to manually moving a single file; look into
    // making this step more efficient
    // may not actually be the fault of adding the tooling step though
    // TODO: look into only copying files that are actually re-compiled
    // not sure if CopyFileA will just ignore old files anyway tho

    const copy_step = b.step(
        "hotcopy",
        "Build and send output to live 'annodue' directory for hot reloading",
    );
    const copypath = b.option(
        []const u8,
        "hotcopypath",
        "Location of output directory for 'hotcopy' step",
    ) orelse null;

    const hotcopy_move_files = b.addExecutable(.{
        .name = "hotcopy_move_files",
        .root_source_file = .{ .path = "src/tools/hotcopy_move_files.zig" },
        .target = target,
    });
    hotcopy_move_files.addModule("zigwin32", zigwin32_m);

    const hotcopy_move_files_core = b.addRunArtifact(hotcopy_move_files);
    const hotcopy_move_files_plugin = b.addRunArtifact(hotcopy_move_files);
    if (copypath) |path| {
        const arg_hci = std.fmt.bufPrint(&buf1, "-I{s}", .{b.lib_dir}) catch unreachable;
        const arg_hcoc = std.fmt.bufPrint(&buf2, "-O{s}", .{path}) catch unreachable;
        const arg_hcop = std.fmt.bufPrint(&buf2, "-O{s}/plugin", .{path}) catch unreachable;

        copy_step.dependOn(&hotcopy_move_files_core.step);
        hotcopy_move_files_core.addArg(arg_hci);
        hotcopy_move_files_core.addArg(arg_hcoc);

        copy_step.dependOn(&hotcopy_move_files_plugin.step);
        hotcopy_move_files_plugin.addArg(arg_hci);
        hotcopy_move_files_plugin.addArg(arg_hcop);
    }

    // STEP - PLUGIN HASHING

    // TODO: direct build step to output file to a directory src can use to
    // include via @embedFile

    const generate_safe_plugin_hash_file = b.addExecutable(.{
        .name = "generate_safe_plugin_hash_file",
        .root_source_file = .{ .path = "src/tools/generate_safe_plugin_hash_file.zig" },
        .target = target,
    });
    generate_safe_plugin_hash_file.addModule("zigwin32", zigwin32_m);

    const generate_safe_plugin_hash_file_plugin = b.addRunArtifact(generate_safe_plugin_hash_file);
    const arg_phi = std.fmt.bufPrint(&buf1, "-I{s}", .{b.lib_dir}) catch unreachable;
    generate_safe_plugin_hash_file_plugin.addArg(arg_phi);

    var hash_step = &generate_safe_plugin_hash_file_plugin.step;

    const hash_plugins_step = b.step(
        "hashfile",
        "Generate valid plugin hashfile",
    );
    hash_plugins_step.dependOn(hash_step);

    // STEP - BUILD PLUGINS

    // TODO: separate build step for test plugin only
    // TODO: reorganize build script to make this more convenient to edit

    var plugin_step = b.step(
        "plugins",
        "Build plugin DLLs",
    );
    hash_step.dependOn(plugin_step);

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
    };

    for (plugins) |plugin| {
        const n = std.fmt.bufPrint(&buf1, "plugin_{s}", .{plugin.name}) catch continue;
        const p = std.fmt.bufPrint(&buf2, "src/patch/dll_{s}.zig", .{plugin.name}) catch continue;
        const dll = b.addSharedLibrary(.{
            .name = n,
            .root_source_file = .{ .path = p },
            .target = target,
            .optimize = optimize,
        });
        dll.linkLibC();
        dll.addModule("zigwin32", zigwin32_m);

        // TODO: investigate options arg
        var dll_install = b.addInstallArtifact(dll, .{});
        plugin_step.dependOn(&dll_install.step);

        var buf: [1024]u8 = undefined;
        var bufo = std.fmt.bufPrint(&buf, "-Fplugin_{s}.dll", .{plugin.name}) catch continue;
        hotcopy_move_files_plugin.addArg(bufo);
        if (plugin.to_hash) generate_safe_plugin_hash_file_plugin.addArg(bufo);
    }

    // STEP - BUILD MAIN DLL

    const core = b.addSharedLibrary(.{
        .name = "annodue",
        .root_source_file = .{ .path = "src/patch/patch.zig" },
        .target = target,
        .optimize = optimize,
    });
    core.linkLibC();
    core.addModule("zigwin32", zigwin32_m);
    core.step.dependOn(hash_step);

    // TODO: investigate options arg
    const core_install = b.addInstallArtifact(core, .{});

    hotcopy_move_files_core.addArg("-Fannodue.dll");
    hotcopy_move_files.step.dependOn(&core_install.step);

    // DEFAULT STEP

    b.default_step.dependOn(&core_install.step);

    // MISC OLD STUFF

    //const dll_install = b.addInstallDirectory(.{
    //    .source_dir = .{ .path = "annodue" },
    //    .install_dir = .{ .custom = "annodue" },
    //    .install_subdir = "",
    //});
    //b.default_step.dependOn(&dll_install.step);

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
