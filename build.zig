const std = @import("std");

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

    // TOOLING

    // FIXME: kinda slow, comparable to manually moving a single file; look into
    // making this step more efficient
    // may not actually be the fault of adding the tooling step though

    const copy_step = b.step(
        "hotcopy",
        "Build and send output to live 'annodue' directory for hot reloading",
    );
    const copypath = b.option(
        []const u8,
        "hotcopypath",
        "Location of output directory for 'hotcopy' step",
    ) orelse null;

    const postbuild = b.addExecutable(.{
        .name = "postbuild",
        .root_source_file = .{ .path = "src/tools/postbuild.zig" },
        .target = target,
    });
    postbuild.addModule("zigwin32", zigwin32_m);
    postbuild.step.dependOn(&b.install_tls.step);

    const postbuild_core = b.addRunArtifact(postbuild);
    const postbuild_plugin = b.addRunArtifact(postbuild);
    if (copypath) |path| {
        const arg_hci = std.fmt.bufPrint(&buf1, "-I{s}", .{b.lib_dir}) catch unreachable;
        const arg_hcoc = std.fmt.bufPrint(&buf2, "-O{s}", .{path}) catch unreachable;
        const arg_hcop = std.fmt.bufPrint(&buf2, "-O{s}/plugin", .{path}) catch unreachable;

        copy_step.dependOn(&postbuild_core.step);
        postbuild_core.addArg(arg_hci);
        postbuild_core.addArg(arg_hcoc);

        copy_step.dependOn(&postbuild_plugin.step);
        postbuild_plugin.addArg(arg_hci);
        postbuild_plugin.addArg(arg_hcop);
    }

    // MAIN OUTPUT

    const patch = b.addSharedLibrary(.{
        .name = "annodue",
        .root_source_file = .{ .path = "src/patch/patch.zig" },
        .target = target,
        .optimize = optimize,
    });
    patch.linkLibC();
    //patch.addModule("zigini", zigini_m);
    patch.addModule("zigwin32", zigwin32_m);
    b.installArtifact(patch);

    postbuild_core.addArg("-Fannodue.dll");

    // PLUGINS OUTPUT

    const plugin_names = &[_][]const u8{
        "test",
        "savestate",
        "qol",
        "overlay",
        "gameplaytweak",
        "cosmetic",
        "multiplayer",
        "developer",
        "inputdisplay",
        "cam7",
    };

    for (plugin_names) |name| {
        const n = std.fmt.bufPrint(&buf1, "plugin_{s}", .{name}) catch continue;
        const p = std.fmt.bufPrint(&buf2, "src/patch/dll_{s}.zig", .{name}) catch continue;
        const dll = b.addSharedLibrary(.{
            .name = n,
            .root_source_file = .{ .path = p },
            .target = target,
            .optimize = optimize,
        });
        dll.linkLibC();
        //dll.addModule("zigini", zigini_m);
        dll.addModule("zigwin32", zigwin32_m);
        b.installArtifact(dll);

        var buf: [1024]u8 = undefined;
        var bufo = std.fmt.bufPrint(&buf, "-Fplugin_{s}.dll", .{name}) catch continue;
        postbuild_plugin.addArg(bufo);
    }

    // TODO: look into only copying files that are actually re-compiled
    // not sure if CopyFileA will just ignore old files anyway tho

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
