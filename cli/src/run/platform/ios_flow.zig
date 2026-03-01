//! iOS platform run orchestration.
//!
//! This module coordinates simulator selection, host build, FFI bundling, and
//! launch/debug behavior for `wizig run ios`.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const app_root = @import("app_root.zig");
const config_parse = @import("config_parse.zig");
const ios_discovery = @import("ios_discovery.zig");
const ios_ffi = @import("ios_ffi.zig");
const ios_launch = @import("ios_launch.zig");
const options_mod = @import("options.zig");
const process = @import("process_supervisor.zig");
const text_utils = @import("text_utils.zig");
const types = @import("types.zig");

/// Executes the full iOS run pipeline.
pub fn runIos(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
) !void {
    if (builtin.os.tag != .macos) {
        try stderr.writeAll("error: iOS run is only supported on macOS hosts\n");
        return error.RunFailed;
    }

    const debugger_mode = try options_mod.resolveIosDebugger(stderr, options.debugger);

    if (options.regenerate_host) {
        try ios_launch.maybeRegenerateIosProject(arena, io, stderr, stdout, options.project_dir);
    }
    const xcode_project = try ios_launch.findXcodeProject(arena, io, stderr, options.project_dir);
    const scheme = options.scheme orelse config_parse.inferSchemeFromProject(xcode_project) orelse {
        try stderr.writeAll("error: failed to infer iOS scheme, pass --scheme\n");
        return error.RunFailed;
    };

    const selected = if (options.skip_device_discovery)
        try resolvePreselectedIosDevice(arena, io, stderr, options.project_dir, xcode_project, scheme, options.device_selector)
    else blk: {
        const all_devices = try ios_discovery.discoverIosDevices(arena, io, stderr);
        if (all_devices.len == 0) {
            try stderr.writeAll("error: no available iOS simulators found\n");
            return error.RunFailed;
        }
        const supported_ids = try ios_discovery.discoverIosSupportedDestinationIds(
            arena,
            io,
            stderr,
            options.project_dir,
            xcode_project,
            scheme,
        );
        const devices = if (supported_ids.len == 0)
            all_devices
        else
            try ios_discovery.filterIosDevicesBySupportedIds(arena, all_devices, supported_ids);
        if (devices.len == 0) {
            try stderr.writeAll("error: no iOS simulators match xcodebuild destinations for this scheme\n");
            return error.RunFailed;
        }

        break :blk try ios_discovery.chooseIosDevice(arena, io, stderr, stdout, devices, options.device_selector, options.non_interactive);
    };

    try stdout.print("selected iOS simulator: {s} [{s}] ({s}, {s})\n", .{ selected.name, selected.udid, selected.runtime, selected.state });
    try stdout.flush();

    _ = process.runCapture(arena, io, .{ .argv = &.{ "xcrun", "simctl", "boot", selected.udid }, .label = "boot iOS simulator" }, .{}) catch null;
    _ = process.runCapture(arena, io, .{ .argv = &.{ "xcrun", "simctl", "bootstatus", selected.udid, "-b" }, .label = "wait iOS bootstatus" }, .{}) catch {};

    const destination = try std.fmt.allocPrint(arena, "id={s}", .{selected.udid});
    const derived_data = try std.fmt.allocPrint(arena, "/tmp/wizig-derived-{s}", .{scheme});

    try stdout.writeAll("building iOS app...\n");
    try stdout.flush();
    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "xcodebuild", "-project", xcode_project, "-scheme", scheme, "-destination", destination, "-derivedDataPath", derived_data, "build" },
        .cwd_path = options.project_dir,
        .label = "build iOS app",
    });

    const settings = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcodebuild", "-project", xcode_project, "-scheme", scheme, "-destination", destination, "-derivedDataPath", derived_data, "-showBuildSettings" },
        .cwd_path = options.project_dir,
        .label = "read iOS build settings",
    }, .{});

    const target_build_dir = config_parse.extractBuildSetting(settings.stdout, "TARGET_BUILD_DIR") orelse {
        try stderr.writeAll("error: failed to read TARGET_BUILD_DIR from xcodebuild settings\n");
        return error.RunFailed;
    };
    const wrapper_name = config_parse.extractBuildSetting(settings.stdout, "WRAPPER_NAME") orelse {
        try stderr.writeAll("error: failed to read WRAPPER_NAME from xcodebuild settings\n");
        return error.RunFailed;
    };
    const bundle_id = options.bundle_id orelse (config_parse.extractBuildSetting(settings.stdout, "PRODUCT_BUNDLE_IDENTIFIER") orelse {
        try stderr.writeAll("error: failed to read PRODUCT_BUNDLE_IDENTIFIER from xcodebuild settings; use --bundle-id\n");
        return error.RunFailed;
    });
    const app_path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ target_build_dir, wrapper_name });

    const app_root_path = try app_root.resolveAppRoot(arena, io, options.project_dir);
    const simulator_ffi_path = try ios_ffi.buildIosSimulatorFfiLibrary(arena, io, stderr, parent_environ_map, app_root_path);
    const runtime_ffi_path = try ios_ffi.bundleIosFfiLibraryForSimulator(arena, io, stderr, app_path, simulator_ffi_path);

    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "xcrun", "simctl", "install", selected.udid, app_path },
        .label = "install iOS app",
    });

    _ = process.runCapture(arena, io, .{ .argv = &.{ "xcrun", "simctl", "terminate", selected.udid, bundle_id }, .label = "terminate previously running iOS app" }, .{}) catch {};

    var launch_env = try parent_environ_map.clone(arena);
    defer launch_env.deinit();
    try launch_env.put("WIZIG_FFI_LIB", runtime_ffi_path);
    try launch_env.put("SIMCTL_CHILD_WIZIG_FFI_LIB", runtime_ffi_path);
    try launch_env.put("SIMCTL_CHILD_NSUnbufferedIO", "YES");
    try launch_env.put("SIMCTL_CHILD_CFLOG_FORCE_STDERR", "YES");
    try launch_env.put("SIMCTL_CHILD_OS_ACTIVITY_MODE", "disable");

    if (debugger_mode == .none and !options.once) {
        try stdout.writeAll("launching iOS app with attached console (close app or Ctrl+C to stop)...\n");
        try stdout.flush();
        try ios_launch.launchIosAppWithConsoleRetry(
            arena,
            io,
            stderr,
            stdout,
            selected.udid,
            bundle_id,
            &launch_env,
            options.monitor_timeout_seconds,
        );
        return;
    }

    const launch = try ios_launch.launchIosAppWithRetry(arena, io, stderr, selected.udid, bundle_id, &launch_env);
    const pid = text_utils.parseLaunchPid(launch.stdout) orelse {
        try stderr.writeAll("error: failed to parse launched iOS app PID\n");
        return error.RunFailed;
    };

    try stdout.print("launched {s} (pid {d})\n", .{ bundle_id, pid });
    try stdout.flush();

    if (options.once) {
        try stdout.writeAll("run completed (--once)\n");
        try stdout.flush();
        return;
    }

    switch (debugger_mode) {
        .lldb => {
            const attach_command = try std.fmt.allocPrint(arena, "process attach --pid {d}", .{pid});
            try stdout.writeAll("attaching lldb (exit lldb to stop wizig run)...\n");
            try stdout.flush();
            try process.runInheritChecked(io, stderr, .{ .argv = &.{ "lldb", "-o", attach_command, "-o", "continue" }, .label = "attach lldb to iOS app" });
        },
        .none => {
            try stdout.writeAll("app launched without debugger\n");
            try stdout.flush();
        },
        else => {
            try stderr.writeAll("error: selected debugger is not valid for iOS\n");
            return error.RunFailed;
        },
    }
}

fn resolvePreselectedIosDevice(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    xcode_project: []const u8,
    scheme: []const u8,
    selector: ?[]const u8,
) !types.IosDevice {
    const udid = selector orelse {
        try stderr.writeAll("error: internal preselected iOS run requires --device\n");
        return error.RunFailed;
    };

    const supported_ids = try ios_discovery.discoverIosSupportedDestinationIds(
        arena,
        io,
        stderr,
        project_dir,
        xcode_project,
        scheme,
    );
    if (supported_ids.len > 0 and !text_utils.containsString(supported_ids, udid)) {
        try stderr.print("error: selected iOS simulator '{s}' is not supported by scheme '{s}'\n", .{ udid, scheme });
        return error.RunFailed;
    }

    return .{ .name = udid, .udid = udid, .runtime = "unknown", .state = "Unknown" };
}
