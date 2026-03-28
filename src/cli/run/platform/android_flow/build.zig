//! Android Gradle build preparation and APK discovery.
//!
//! This module owns the host-managed FFI Gradle setup so the main flow can
//! stay focused on orchestration.
const std = @import("std");
const Io = std.Io;

const android_app_info = @import("../android_app_info.zig");
const android_gradle_init = @import("../android_gradle_init.zig");
const android_gradle_migration = @import("../android_gradle_migration.zig");
const android_jni_bridge_migration = @import("../android_jni_bridge_migration.zig");
const android_build_plan = @import("../android_build_plan.zig");
const fs_utils = @import("../fs_utils.zig");
const process = @import("../process_supervisor.zig");
const tooling = @import("../tooling.zig");

/// Prepared Android build inputs and environment state.
pub const AndroidBuildState = struct {
    gradle_env: std.process.Environ.Map,
    gradle_init_script: []const u8,
    gradle_cmd: []const u8,
    assemble_task: []const u8,
    ffi_plan: android_build_plan.HostManagedAndroidFfiPlan,
};

/// Prepares Gradle environment, runs compatibility migrations, and resolves build inputs.
pub fn prepareAndroidBuild(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_dir: []const u8,
    module: []const u8,
    ffi_plan: android_build_plan.HostManagedAndroidFfiPlan,
) !AndroidBuildState {
    const gradle_home = "/tmp/wizig-gradle-home";
    std.Io.Dir.cwd().createDirPath(io, gradle_home) catch {};

    const migration_summary = android_gradle_migration.ensureBuildGradleKtsCompatibility(
        arena,
        io,
        project_dir,
        module,
    ) catch |err| blk: {
        try stderr.print(
            "warning: failed to run Android Gradle compatibility migration: {s}\n",
            .{@errorName(err)},
        );
        break :blk android_gradle_migration.MigrationSummary{};
    };
    if (migration_summary.patched) {
        try stdout.writeAll("patched Android host Gradle compatibility for FFI task wiring\n");
        try stdout.flush();
    }

    const jni_bridge_migration_summary = android_jni_bridge_migration.ensureGeneratedJniBridgeCompatibility(
        arena,
        io,
        project_dir,
    ) catch |err| blk: {
        try stderr.print(
            "warning: failed to run Android JNI bridge compatibility migration: {s}\n",
            .{@errorName(err)},
        );
        break :blk android_jni_bridge_migration.MigrationSummary{};
    };
    if (jni_bridge_migration_summary.patched) {
        try stdout.writeAll("patched Android JNI bridge to forward Zig stdio to logcat\n");
        try stdout.flush();
    }

    var gradle_env = try parent_environ_map.clone(arena);
    errdefer gradle_env.deinit();
    try gradle_env.put("GRADLE_USER_HOME", gradle_home);

    const gradle_init_script = try android_gradle_init.ensureInitScript(arena, io, gradle_home);
    const gradle_wrapper_path = try fs_utils.joinPath(arena, project_dir, "gradlew");
    const gradle_wrapper_jar_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}gradle{s}wrapper{s}gradle-wrapper.jar",
        .{ project_dir, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );
    const has_wrapper_script = fs_utils.pathExists(io, gradle_wrapper_path);
    const has_wrapper_jar = fs_utils.pathExists(io, gradle_wrapper_jar_path);
    if (has_wrapper_script and !has_wrapper_jar) {
        try stdout.writeAll("warning: gradle wrapper jar is missing; falling back to system gradle\n");
        try stdout.flush();
    }

    const gradle_cmd = selectGradleCommand(has_wrapper_script, has_wrapper_jar);
    if (std.mem.eql(u8, gradle_cmd, "gradle") and !tooling.commandExists(arena, io, "gradle")) {
        try stderr.writeAll("error: gradle wrapper is incomplete and system gradle is not installed\n");
        return error.RunFailed;
    }

    const assemble_task = try std.fmt.allocPrint(arena, ":{s}:assembleDebug", .{module});
    return .{
        .gradle_env = gradle_env,
        .gradle_init_script = gradle_init_script,
        .gradle_cmd = gradle_cmd,
        .assemble_task = assemble_task,
        .ffi_plan = ffi_plan,
    };
}

/// Builds the Android app and returns the debug APK path.
pub fn runAndroidBuild(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_dir: []const u8,
    module: []const u8,
    state: AndroidBuildState,
) ![]const u8 {
    try stdout.writeAll("building Android app (host-managed FFI)...\n");
    try stdout.flush();
    try process.runInheritChecked(io, stderr, .{
        .argv = &.{
            state.gradle_cmd,
            "--no-daemon",
            "-I",
            state.gradle_init_script,
            state.ffi_plan.injected_build_abi_property,
            state.ffi_plan.wizig_ffi_abi_property,
            "-Pwizig.ffi.optimize=Debug",
            state.assemble_task,
        },
        .cwd_path = project_dir,
        .environ_map = &state.gradle_env,
        .label = "build Android app",
    });
    return android_app_info.findDebugApk(arena, io, stderr, project_dir, module);
}

/// Selects the Gradle wrapper when both the script and jar are available.
pub fn selectGradleCommand(has_wrapper_script: bool, has_wrapper_jar: bool) []const u8 {
    return if (has_wrapper_script and has_wrapper_jar) "./gradlew" else "gradle";
}

test "selectGradleCommand uses wrapper only when script and jar are present" {
    try std.testing.expectEqualStrings("./gradlew", selectGradleCommand(true, true));
    try std.testing.expectEqualStrings("gradle", selectGradleCommand(true, false));
    try std.testing.expectEqualStrings("gradle", selectGradleCommand(false, true));
    try std.testing.expectEqualStrings("gradle", selectGradleCommand(false, false));
}
