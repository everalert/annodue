const std = @import("std");

pub fn build(b: *std.Build) void {
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

    const patch = b.addSharedLibrary(.{
        .name = "annodue",
        .root_source_file = .{ .path = "src/patch/patch.zig" },
        .target = target,
        .optimize = optimize,
    });
    patch.linkLibC();
    b.installArtifact(patch);

    const dll_test = b.addSharedLibrary(.{
        .name = "plugin_test",
        .root_source_file = .{ .path = "src/patch/dll_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    dll_test.linkLibC();
    b.installArtifact(dll_test);

    const dll_savestate = b.addSharedLibrary(.{
        .name = "plugin_savestate",
        .root_source_file = .{ .path = "src/patch/dll_savestate.zig" },
        .target = target,
        .optimize = optimize,
    });
    dll_savestate.linkLibC();
    b.installArtifact(dll_savestate);

    const dll_qol = b.addSharedLibrary(.{
        .name = "plugin_qol",
        .root_source_file = .{ .path = "src/patch/dll_qol.zig" },
        .target = target,
        .optimize = optimize,
    });
    dll_qol.linkLibC();
    b.installArtifact(dll_qol);

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
