//! Wizig build graph.
//!
//! This file defines build/install targets for:
//! - CLI executable (`wizig`)
//! - Core and compatibility modules
//! - FFI static/shared libraries
//! - Installed SDK/runtime/templates assets
const std = @import("std");

/// Configures all build steps for Wizig.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option([]const u8, "version", "Embedded version string") orelse "dev";

    const core_module = b.addModule("wizig_core", .{
        .root_source_file = b.path("core/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("wizig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wizig_core", .module = core_module },
        },
    });

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);

    const cli_module = b.createModule(.{
        .root_source_file = b.path("cli/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wizig_core", .module = core_module },
            .{ .name = "build_options", .module = build_options.createModule() },
        },
    });

    const exe = b.addExecutable(.{
        .name = "wizig",
        .root_module = cli_module,
    });
    b.installArtifact(exe);

    const install_sdk = b.addInstallDirectory(.{
        .source_dir = b.path("sdk"),
        .install_dir = .prefix,
        .install_subdir = "share/wizig/sdk",
    });
    b.getInstallStep().dependOn(&install_sdk.step);

    const install_runtime = b.addInstallDirectory(.{
        .source_dir = b.path("runtime"),
        .install_dir = .prefix,
        .install_subdir = "share/wizig/runtime",
    });
    b.getInstallStep().dependOn(&install_runtime.step);

    const generate_templates = b.addSystemCommand(&.{
        "python3",
        "tools/templategen/generate_templates.py",
        "--out",
        "build/generated/templates",
    });

    const install_templates = b.addInstallDirectory(.{
        .source_dir = b.path("build/generated/templates"),
        .install_dir = .prefix,
        .install_subdir = "share/wizig/templates",
    });
    install_templates.step.dependOn(&generate_templates.step);
    b.getInstallStep().dependOn(&install_templates.step);
    const install_toolchains = b.addInstallFile(b.path("toolchains.toml"), "share/wizig/toolchains.toml");
    b.getInstallStep().dependOn(&install_toolchains.step);

    const ffi_module = b.createModule(.{
        .root_source_file = b.path("ffi/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wizig_core", .module = core_module },
        },
    });
    const ffi_static_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "wizigffi",
        .root_module = ffi_module,
    });
    b.installArtifact(ffi_static_lib);

    const ffi_shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "wizigffi",
        .root_module = ffi_module,
    });
    b.installArtifact(ffi_shared_lib);

    const install_header = b.addInstallHeaderFile(b.path("ffi/include/wizig.h"), "wizig.h");
    b.getInstallStep().dependOn(&install_header.step);

    const run_step = b.step("run", "Run the Wizig CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const docs_step = b.step("docs", "Generate Wizig documentation site");
    const docs_toolchains_cmd = b.addSystemCommand(&.{ "python3", "tools/toolchains/render_docs.py" });
    const docs_ref_cmd = b.addSystemCommand(&.{ "python3", "scripts/docs_build.py", "--reference-only" });
    docs_ref_cmd.step.dependOn(&docs_toolchains_cmd.step);
    const docs_mkdocs_cmd = b.addSystemCommand(&.{ "mkdocs", "build" });
    docs_mkdocs_cmd.step.dependOn(&docs_ref_cmd.step);
    docs_step.dependOn(&docs_mkdocs_cmd.step);

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
                .{ .name = "wizig_core", .module = core_module },
            },
        }),
    });
    const run_ffi_tests = b.addRunArtifact(ffi_tests);

    const runtime_ffi_tests = b.addTest(.{
        .name = "runtime-ffi-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/ffi/src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wizig_core", .module = core_module },
            },
        }),
    });
    const run_runtime_ffi_tests = b.addRunArtifact(runtime_ffi_tests);

    const compatibility_tests = b.addTest(.{
        .name = "compatibility-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wizig_core", .module = core_module },
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
                .{ .name = "wizig_core", .module = core_module },
            },
        }),
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_ffi_tests.step);
    test_step.dependOn(&run_runtime_ffi_tests.step);
    test_step.dependOn(&run_compatibility_tests.step);
    test_step.dependOn(&run_cli_tests.step);

    const e2e_step = b.step("e2e", "Run end-to-end scaffold/run checks");
    const e2e_cmd = b.addSystemCommand(&.{ "/bin/bash", "scripts/e2e/self_contained_template_pipeline.sh" });
    e2e_cmd.step.dependOn(b.getInstallStep());
    e2e_cmd.setEnvironmentVariable("WIZIG_TESTS_ROOT", "/tmp/wizig-e2e");
    e2e_cmd.setEnvironmentVariable("WIZIG_E2E_TEST_ROOT", "/tmp/wizig-e2e");
    e2e_step.dependOn(&e2e_cmd.step);
}
