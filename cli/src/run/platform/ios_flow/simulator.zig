//! iOS simulator build, bundling, and launch flow.
const std = @import("std");

const app_root = @import("../app_root.zig");
const config_parse = @import("../config_parse.zig");
const ios_ffi = @import("../ios_ffi.zig");
const ios_launch = @import("../ios_launch.zig");
const process = @import("../process_supervisor.zig");
const text_utils = @import("../text_utils.zig");
const types = @import("../types.zig");

const context = @import("context.zig");
const debug_flow = @import("debug.zig");

const BuildArtifacts = struct {
    bundle_id: []const u8,
    app_path: []const u8,
};

/// Runs the simulator build, install, and launch pipeline.
pub fn run(ctx: *const context.RunContext, selected: types.IosDevice) !void {
    _ = process.runCapture(ctx.arena, ctx.io, .{ .argv = &.{ "xcrun", "simctl", "boot", selected.udid }, .label = "boot iOS simulator" }, .{}) catch null;
    _ = process.runCapture(ctx.arena, ctx.io, .{ .argv = &.{ "xcrun", "simctl", "bootstatus", selected.udid, "-b" }, .label = "wait iOS bootstatus" }, .{}) catch {};

    const destination = try std.fmt.allocPrint(ctx.arena, "id={s}", .{selected.udid});
    const derived_data = try std.fmt.allocPrint(ctx.arena, "/tmp/wizig-derived-{s}", .{ctx.scheme});

    try ctx.stdout.writeAll("building iOS app...\n");
    try ctx.stdout.flush();
    try process.runInheritChecked(ctx.io, ctx.stderr, .{
        .argv = &.{ "xcodebuild", "-project", ctx.xcode_project, "-scheme", ctx.scheme, "-destination", destination, "-derivedDataPath", derived_data, "build" },
        .cwd_path = ctx.options.project_dir,
        .label = "build iOS app",
    });

    const settings = try process.runCaptureChecked(ctx.arena, ctx.io, ctx.stderr, .{
        .argv = &.{ "xcodebuild", "-project", ctx.xcode_project, "-scheme", ctx.scheme, "-destination", destination, "-derivedDataPath", derived_data, "-showBuildSettings" },
        .cwd_path = ctx.options.project_dir,
        .label = "read iOS build settings",
    }, .{});

    const build = try readBuildArtifacts(ctx, settings.stdout);

    const app_root_path = try app_root.resolveAppRoot(ctx.arena, ctx.io, ctx.options.project_dir);
    const simulator_ffi_path = try ios_ffi.buildIosSimulatorFfiLibrary(ctx.arena, ctx.io, ctx.stderr, ctx.parent_environ_map, app_root_path);
    _ = try ios_ffi.bundleIosFfiLibraryForSimulator(ctx.arena, ctx.io, ctx.stderr, build.app_path, simulator_ffi_path);

    try process.runInheritChecked(ctx.io, ctx.stderr, .{
        .argv = &.{ "xcrun", "simctl", "install", selected.udid, build.app_path },
        .label = "install iOS app",
    });

    _ = process.runCapture(ctx.arena, ctx.io, .{ .argv = &.{ "xcrun", "simctl", "terminate", selected.udid, build.bundle_id }, .label = "terminate previously running iOS app" }, .{}) catch {};

    var launch_env = try ctx.parent_environ_map.clone(ctx.arena);
    defer launch_env.deinit();
    try launch_env.put("SIMCTL_CHILD_NSUnbufferedIO", "YES");
    try launch_env.put("SIMCTL_CHILD_CFLOG_FORCE_STDERR", "YES");
    try launch_env.put("SIMCTL_CHILD_OS_ACTIVITY_MODE", "disable");

    if (ctx.debugger_mode == .none and !ctx.options.once) {
        try ctx.stdout.writeAll("launching iOS app with attached console (close app or Ctrl+C to stop)...\n");
        try ctx.stdout.flush();
        try ios_launch.launchIosAppWithConsoleRetry(
            ctx.arena,
            ctx.io,
            ctx.stderr,
            ctx.stdout,
            selected.udid,
            build.bundle_id,
            &launch_env,
            ctx.options.monitor_timeout_seconds,
        );
        return;
    }

    const launch = try ios_launch.launchIosAppWithRetry(ctx.arena, ctx.io, ctx.stderr, selected.udid, build.bundle_id, &launch_env);
    const pid = text_utils.parseLaunchPid(launch.stdout) orelse {
        try ctx.stderr.writeAll("error: failed to parse launched iOS app PID\n");
        return error.RunFailed;
    };

    try ctx.stdout.print("launched {s} (pid {d})\n", .{ build.bundle_id, pid });
    try ctx.stdout.flush();

    if (ctx.options.once) {
        try ctx.stdout.writeAll("run completed (--once)\n");
        try ctx.stdout.flush();
        return;
    }

    try debug_flow.attachDebuggerIfNeeded(ctx.arena, ctx.io, ctx.stderr, ctx.stdout, ctx.debugger_mode, pid);
}

/// Reads build settings that the simulator flow needs after the Xcode build completes.
fn readBuildArtifacts(ctx: *const context.RunContext, settings_stdout: []const u8) !BuildArtifacts {
    const target_build_dir = config_parse.extractBuildSetting(settings_stdout, "TARGET_BUILD_DIR") orelse {
        try ctx.stderr.writeAll("error: failed to read TARGET_BUILD_DIR from xcodebuild settings\n");
        return error.RunFailed;
    };
    const wrapper_name = config_parse.extractBuildSetting(settings_stdout, "WRAPPER_NAME") orelse {
        try ctx.stderr.writeAll("error: failed to read WRAPPER_NAME from xcodebuild settings\n");
        return error.RunFailed;
    };
    const bundle_id = ctx.options.bundle_id orelse (config_parse.extractBuildSetting(settings_stdout, "PRODUCT_BUNDLE_IDENTIFIER") orelse {
        try ctx.stderr.writeAll("error: failed to read PRODUCT_BUNDLE_IDENTIFIER from xcodebuild settings; use --bundle-id\n");
        return error.RunFailed;
    });

    return .{
        .bundle_id = bundle_id,
        .app_path = try std.fmt.allocPrint(ctx.arena, "{s}/{s}", .{ target_build_dir, wrapper_name }),
    };
}
