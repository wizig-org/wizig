const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_module = b.addModule("ziggy_core", .{
        .root_source_file = b.path("core/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("ziggy", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ziggy_core", .module = core_module },
        },
    });

    const cli_module = b.createModule(.{
        .root_source_file = b.path("cli/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ziggy_core", .module = core_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "ziggy",
        .root_module = cli_module,
    });
    b.installArtifact(exe);

    const ffi_module = b.createModule(.{
        .root_source_file = b.path("ffi/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ziggy_core", .module = core_module },
        },
    });
    const ffi_static_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ziggyffi",
        .root_module = ffi_module,
    });
    b.installArtifact(ffi_static_lib);

    const ffi_shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "ziggyffi",
        .root_module = ffi_module,
    });
    b.installArtifact(ffi_shared_lib);

    const install_header = b.addInstallHeaderFile(b.path("ffi/include/ziggy.h"), "ziggy.h");
    b.getInstallStep().dependOn(&install_header.step);

    const run_step = b.step("run", "Run the Ziggy CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const core_tests = b.addTest(.{
        .name = "core-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("core/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_core_tests = b.addRunArtifact(core_tests);

    const ffi_tests = b.addTest(.{
        .name = "ffi-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("ffi/src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ziggy_core", .module = core_module },
            },
        }),
    });
    const run_ffi_tests = b.addRunArtifact(ffi_tests);

    const compatibility_tests = b.addTest(.{
        .name = "compatibility-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ziggy_core", .module = core_module },
            },
        }),
    });
    const run_compatibility_tests = b.addRunArtifact(compatibility_tests);

    const cli_tests = b.addTest(.{
        .name = "cli-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cli/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ziggy_core", .module = core_module },
            },
        }),
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_ffi_tests.step);
    test_step.dependOn(&run_compatibility_tests.step);
    test_step.dependOn(&run_cli_tests.step);
}
