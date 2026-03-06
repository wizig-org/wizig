//! iOS platform run orchestration.
//!
//! This module coordinates simulator/device selection, host build, FFI bundling,
//! and launch/debug behavior for `wizig run ios`.  Physical device support uses
//! `xcrun devicectl` for installation and launch.
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
        // Discover both simulators and physical devices.
        var all_targets = std.ArrayList(types.IosDevice).empty;
        defer all_targets.deinit(arena);

        const simulators = try ios_discovery.discoverIosDevices(arena, io, stderr);
        const supported_ids = try ios_discovery.discoverIosSupportedDestinationIds(
            arena,
            io,
            stderr,
            options.project_dir,
            xcode_project,
            scheme,
        );
        const filtered_sims = if (supported_ids.len == 0)
            simulators
        else
            try ios_discovery.filterIosDevicesBySupportedIds(arena, simulators, supported_ids);

        for (filtered_sims) |sim| {
            try all_targets.append(arena, sim);
        }

        const physical = ios_discovery.discoverIosPhysicalDevices(arena, io) catch &[_]types.IosDevice{};
        for (physical) |dev| {
            try all_targets.append(arena, dev);
        }

        if (all_targets.items.len == 0) {
            try stderr.writeAll("error: no available iOS simulators or devices found\n");
            return error.RunFailed;
        }

        const targets = try all_targets.toOwnedSlice(arena);
        break :blk try ios_discovery.chooseIosDevice(arena, io, stderr, stdout, targets, options.device_selector, options.non_interactive);
    };

    const kind_label: []const u8 = switch (selected.kind) {
        .simulator => "simulator",
        .device => "device",
    };
    try stdout.print("selected iOS {s}: {s} [{s}] ({s}, {s})\n", .{ kind_label, selected.name, selected.udid, selected.runtime, selected.state });
    try stdout.flush();

    switch (selected.kind) {
        .simulator => try runIosSimulator(arena, io, parent_environ_map, stderr, stdout, options, selected, xcode_project, scheme, debugger_mode),
        .device => try runIosDevice(arena, io, parent_environ_map, stderr, stdout, options, selected, xcode_project, scheme, debugger_mode),
    }
}

// ---------------------------------------------------------------------------
// Simulator flow
// ---------------------------------------------------------------------------

fn runIosSimulator(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
    selected: types.IosDevice,
    xcode_project: []const u8,
    scheme: []const u8,
    debugger_mode: types.DebuggerMode,
) !void {
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
    _ = try ios_ffi.bundleIosFfiLibraryForSimulator(arena, io, stderr, app_path, simulator_ffi_path);

    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "xcrun", "simctl", "install", selected.udid, app_path },
        .label = "install iOS app",
    });

    _ = process.runCapture(arena, io, .{ .argv = &.{ "xcrun", "simctl", "terminate", selected.udid, bundle_id }, .label = "terminate previously running iOS app" }, .{}) catch {};

    var launch_env = try parent_environ_map.clone(arena);
    defer launch_env.deinit();
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

    try attachDebuggerIfNeeded(arena, io, stderr, stdout, debugger_mode, pid);
}

// ---------------------------------------------------------------------------
// Physical device flow
// ---------------------------------------------------------------------------

fn runIosDevice(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
    selected: types.IosDevice,
    xcode_project: []const u8,
    scheme: []const u8,
    debugger_mode: types.DebuggerMode,
) !void {
    const destination = try std.fmt.allocPrint(arena, "id={s}", .{selected.udid});
    const derived_data = try std.fmt.allocPrint(arena, "/tmp/wizig-derived-{s}", .{scheme});

    try stdout.writeAll("building iOS app for device...\n");
    try stdout.flush();

    // Build with automatic signing (CODE_SIGN_STYLE=Automatic is set in
    // the project by the codegen patching pipeline).
    try process.runInheritChecked(io, stderr, .{
        .argv = &.{
            "xcodebuild",
            "-project",
            xcode_project,
            "-scheme",
            scheme,
            "-destination",
            destination,
            "-derivedDataPath",
            derived_data,
            "-allowProvisioningUpdates",
            "build",
        },
        .cwd_path = options.project_dir,
        .label = "build iOS device app",
    });

    const settings = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "xcodebuild", "-project", xcode_project, "-scheme", scheme, "-destination", destination, "-derivedDataPath", derived_data, "-showBuildSettings" },
        .cwd_path = options.project_dir,
        .label = "read iOS device build settings",
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

    // Resolve the signing identity used by the Xcode build so the FFI
    // framework gets the matching signature.  EXPANDED_CODE_SIGN_IDENTITY
    // is a derived setting that may not appear in `-showBuildSettings`
    // output, so fall back through several alternatives.
    const sign_identity = config_parse.extractBuildSetting(settings.stdout, "EXPANDED_CODE_SIGN_IDENTITY") orelse
        config_parse.extractBuildSetting(settings.stdout, "EXPANDED_CODE_SIGN_IDENTITY_NAME") orelse
        config_parse.extractBuildSetting(settings.stdout, "CODE_SIGN_IDENTITY");

    // Build and embed the device FFI framework into the built .app bundle.
    const app_root_path = try app_root.resolveAppRoot(arena, io, options.project_dir);
    const device_ffi_path = try ios_ffi.buildIosDeviceFfiLibrary(arena, io, stderr, parent_environ_map, app_root_path);
    _ = try ios_ffi.bundleIosFfiLibraryForDevice(arena, io, stderr, app_path, device_ffi_path, sign_identity);

    // Install on the physical device via devicectl.
    try stdout.writeAll("installing app on device...\n");
    try stdout.flush();
    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "xcrun", "devicectl", "device", "install", "app", "--device", selected.udid, app_path },
        .label = "install iOS app on device",
    });

    // Terminate any previously running instance.  devicectl does not offer a
    // direct "terminate by bundle-id" command, so we best-effort ignore
    // failures here — the new launch will replace the running process.

    // Launch on the device.
    try stdout.writeAll("launching app on device...\n");
    try stdout.flush();

    if (debugger_mode == .none and !options.once) {
        try launchIosDeviceAppWithConsole(arena, io, stderr, stdout, selected.udid, bundle_id, parent_environ_map, options.monitor_timeout_seconds);
        return;
    }

    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "xcrun", "devicectl", "device", "process", "launch", "--device", selected.udid, "--bundle-id", bundle_id },
        .label = "launch iOS device app",
    });

    try stdout.print("launched {s} on device {s}\n", .{ bundle_id, selected.name });
    try stdout.flush();

    if (options.once) {
        try stdout.writeAll("run completed (--once)\n");
        try stdout.flush();
        return;
    }

    // For device debugging with lldb, instruct the user to use Xcode's
    // wireless debugging workflow since attaching to a device process from
    // the CLI requires a developer disk image to be mounted.
    switch (debugger_mode) {
        .lldb => {
            try stdout.writeAll("hint: for device debugging, use Xcode > Debug > Attach to Process\n");
            try stdout.flush();
        },
        else => {},
    }
}

/// Launches an app on a physical device and streams device logs.
fn launchIosDeviceAppWithConsole(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    udid: []const u8,
    bundle_id: []const u8,
    parent_environ_map: *const std.process.Environ.Map,
    monitor_timeout_seconds: ?u64,
) !void {
    // Launch the app first.
    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "xcrun", "devicectl", "device", "process", "launch", "--device", udid, "--bundle-id", bundle_id },
        .label = "launch iOS device app",
    });

    try stdout.print("launched {s} on device\n", .{bundle_id});
    try stdout.writeAll("streaming device log (Ctrl+C to stop)...\n");
    try stdout.flush();

    // Stream the device unified log using `log stream --device`.  This is
    // the standard macOS/iOS log streaming tool and works with physical
    // devices when a valid pairing exists.  We filter by the app's bundle
    // identifier via a predicate to reduce noise.
    const predicate = try std.fmt.allocPrint(arena, "subsystem == \"{s}\" OR process == \"{s}\"", .{ bundle_id, bundle_id });

    const watchdog: process.MonitorWatchdog = .{
        .timeout_seconds = monitor_timeout_seconds,
        .liveness_probe = null,
    };

    _ = try process.runInheritMonitored(
        arena,
        io,
        stderr,
        stdout,
        .{
            .argv = &.{ "log", "stream", "--device", udid, "--predicate", predicate, "--style", "compact" },
            .environ_map = parent_environ_map,
            .label = "stream iOS device log",
        },
        watchdog,
    );
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

fn attachDebuggerIfNeeded(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    debugger_mode: types.DebuggerMode,
    pid: u64,
) !void {
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

    // Check if this is a physical device first.
    const physical = ios_discovery.discoverIosPhysicalDevices(arena, io) catch &[_]types.IosDevice{};
    for (physical) |dev| {
        if (std.mem.eql(u8, dev.udid, udid)) return dev;
    }

    // Fall back to simulator validation.
    const supported_ids = try ios_discovery.discoverIosSupportedDestinationIds(
        arena,
        io,
        stderr,
        project_dir,
        xcode_project,
        scheme,
    );
    if (supported_ids.len > 0 and !text_utils.containsString(supported_ids, udid)) {
        try stderr.print("error: selected iOS target '{s}' is not supported by scheme '{s}'\n", .{ udid, scheme });
        return error.RunFailed;
    }

    return .{ .name = udid, .udid = udid, .runtime = "unknown", .state = "Unknown", .kind = .simulator };
}
