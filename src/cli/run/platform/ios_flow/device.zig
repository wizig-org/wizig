//! iOS physical device build, signing, and launch flow.
const std = @import("std");
const Io = std.Io;

const app_root = @import("../app_root.zig");
const config_parse = @import("../config_parse.zig");
const ios_ffi = @import("../ios_ffi.zig");
const process = @import("../process_supervisor.zig");
const types = @import("../types.zig");

const context = @import("context.zig");

const BuildArtifacts = struct {
    bundle_id: []const u8,
    app_path: []const u8,
};

/// Runs the device build, signing, install, and launch pipeline.
pub fn run(ctx: *const context.RunContext, selected: types.IosDevice) !void {
    const destination = try std.fmt.allocPrint(ctx.arena, "id={s}", .{selected.udid});
    const derived_data = try std.fmt.allocPrint(ctx.arena, "/tmp/wizig-derived-{s}", .{ctx.scheme});

    try ctx.stdout.writeAll("building iOS app for device...\n");
    try ctx.stdout.flush();

    // Build with automatic signing (CODE_SIGN_STYLE=Automatic is set in
    // the project by the codegen patching pipeline).
    try process.runInheritChecked(ctx.io, ctx.stderr, .{
        .argv = &.{
            "xcodebuild",
            "-project",
            ctx.xcode_project,
            "-scheme",
            ctx.scheme,
            "-destination",
            destination,
            "-derivedDataPath",
            derived_data,
            "-allowProvisioningUpdates",
            "build",
        },
        .cwd_path = ctx.options.project_dir,
        .label = "build iOS device app",
    });

    const settings = try process.runCaptureChecked(ctx.arena, ctx.io, ctx.stderr, .{
        .argv = &.{ "xcodebuild", "-project", ctx.xcode_project, "-scheme", ctx.scheme, "-destination", destination, "-derivedDataPath", derived_data, "-showBuildSettings" },
        .cwd_path = ctx.options.project_dir,
        .label = "read iOS device build settings",
    }, .{});

    const build = try readBuildArtifacts(ctx, settings.stdout);

    // Resolve the signing identity used by the Xcode build so the FFI
    // framework gets the matching signature.  EXPANDED_CODE_SIGN_IDENTITY
    // is a derived setting that may not appear in `-showBuildSettings`
    // output, so fall back through several alternatives.
    const sign_identity = config_parse.extractBuildSetting(settings.stdout, "EXPANDED_CODE_SIGN_IDENTITY") orelse
        config_parse.extractBuildSetting(settings.stdout, "EXPANDED_CODE_SIGN_IDENTITY_NAME") orelse
        config_parse.extractBuildSetting(settings.stdout, "CODE_SIGN_IDENTITY");

    // Build and embed the device FFI framework into the built .app bundle.
    const app_root_path = try app_root.resolveAppRoot(ctx.arena, ctx.io, ctx.options.project_dir);
    const device_ffi_path = try ios_ffi.buildIosDeviceFfiLibrary(ctx.arena, ctx.io, ctx.stderr, ctx.parent_environ_map, app_root_path);
    const bundle_result = try ios_ffi.bundleIosFfiLibraryForDeviceDetailed(
        ctx.arena,
        ctx.io,
        ctx.stderr,
        build.app_path,
        device_ffi_path,
        sign_identity,
    );

    // Re-sign the app bundle so its code seal covers the freshly embedded
    // framework.  xcodebuild signs the bundle during the build step above,
    // but post-build FFI embedding modifies the Frameworks/ directory which
    // invalidates the seal.  Without this re-sign iOS refuses to dlopen the
    // framework on real devices (ABI version returns 0, contract hash empty).
    if (bundle_result.changed) {
        const identity = if (sign_identity) |id| (if (id.len != 0) id else null) else null;
        if (identity) |id| {
            _ = try process.runCaptureChecked(ctx.arena, ctx.io, ctx.stderr, .{
                .argv = &.{ "/usr/bin/codesign", "--force", "--sign", id, "--preserve-metadata=entitlements", "--timestamp=none", build.app_path },
                .label = "re-sign iOS device app after FFI embedding",
            }, .{});
        }
    }

    // Install on the physical device via devicectl.
    try ctx.stdout.writeAll("installing app on device...\n");
    try ctx.stdout.flush();
    try process.runInheritChecked(ctx.io, ctx.stderr, .{
        .argv = &.{ "xcrun", "devicectl", "device", "install", "app", "--device", selected.udid, build.app_path },
        .label = "install iOS app on device",
    });

    // Terminate any previously running instance.  devicectl does not offer a
    // direct "terminate by bundle-id" command, so we best-effort ignore
    // failures here - the new launch will replace the running process.

    // Launch on the device.
    try ctx.stdout.writeAll("launching app on device...\n");
    try ctx.stdout.flush();

    if (ctx.debugger_mode == .none and !ctx.options.once) {
        try launchIosDeviceAppWithConsole(ctx.arena, ctx.io, ctx.stderr, ctx.stdout, selected.udid, build.bundle_id, ctx.parent_environ_map, ctx.options.monitor_timeout_seconds);
        return;
    }

    try process.runInheritChecked(ctx.io, ctx.stderr, .{
        .argv = &.{ "xcrun", "devicectl", "device", "process", "launch", "--device", selected.udid, "--bundle-id", build.bundle_id },
        .label = "launch iOS device app",
    });

    try ctx.stdout.print("launched {s} on device {s}\n", .{ build.bundle_id, selected.name });
    try ctx.stdout.flush();

    if (ctx.options.once) {
        try ctx.stdout.writeAll("run completed (--once)\n");
        try ctx.stdout.flush();
        return;
    }

    // For device debugging with lldb, instruct the user to use Xcode's
    // wireless debugging workflow since attaching to a device process from
    // the CLI requires a developer disk image to be mounted.
    switch (ctx.debugger_mode) {
        .lldb => {
            try ctx.stdout.writeAll("hint: for device debugging, use Xcode > Debug > Attach to Process\n");
            try ctx.stdout.flush();
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

/// Reads build settings that the device flow needs after the Xcode build completes.
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
