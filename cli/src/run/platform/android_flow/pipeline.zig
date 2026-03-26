//! Android run pipeline orchestration.
//!
//! This module stitches together target selection, build preparation, launch
//! metadata resolution, and app install/attach handling.
const std = @import("std");
const Io = std.Io;

const android_ffi = @import("../android_ffi.zig");
const android_build_plan = @import("../android_build_plan.zig");
const options_mod = @import("../options.zig");
const types = @import("../types.zig");

const build = @import("build.zig");
const launch = @import("launch.zig");
const metadata = @import("metadata.zig");
const selection = @import("selection.zig");

/// Executes the full Android run pipeline.
pub fn runAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
) !void {
    const debugger_mode = try options_mod.resolveAndroidDebugger(arena, io, stderr, options.debugger);

    const selected = try selection.resolveAndroidTarget(arena, io, stderr, stdout, options);
    try stdout.print("selected Android target: {s} [{s}]\n", .{ selected.model, selected.serial });
    try stdout.flush();

    const resolved_abi = try android_ffi.resolveAndroidDeviceAbi(arena, io, stderr, selected.serial);
    const ffi_plan = android_build_plan.planHostManagedAndroidFfiBuild(arena, resolved_abi) catch {
        try stderr.print("error: unsupported Android ABI '{s}'\n", .{resolved_abi});
        return error.RunFailed;
    };
    try stdout.print("selected Android FFI ABI: {s} ({s})\n", .{ ffi_plan.abi, ffi_plan.zig_target });
    try stdout.flush();

    var build_state = try build.prepareAndroidBuild(
        arena,
        io,
        parent_environ_map,
        stderr,
        stdout,
        options.project_dir,
        options.module,
        ffi_plan,
    );
    defer build_state.gradle_env.deinit();

    const apk = try build.runAndroidBuild(
        arena,
        io,
        stderr,
        stdout,
        options.project_dir,
        options.module,
        build_state,
    );

    const launch_metadata = try metadata.resolveAndroidLaunchMetadata(
        arena,
        io,
        stderr,
        options.project_dir,
        options.module,
        apk,
        options.app_id,
        options.activity,
    );

    try launch.launchAndroidApp(
        arena,
        io,
        stderr,
        stdout,
        selected.serial,
        apk,
        launch_metadata,
        debugger_mode,
        options.once,
        options.monitor_timeout_seconds,
    );
}
