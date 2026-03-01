//! Android platform run orchestration.
//!
//! This module coordinates target selection, FFI prep, Gradle build, install,
//! launch, and optional debugger/log monitor attachment for Android runs.
const std = @import("std");
const Io = std.Io;

const app_root = @import("app_root.zig");
const android_app_info = @import("android_app_info.zig");
const android_debug = @import("android_debug.zig");
const android_discovery = @import("android_discovery.zig");
const android_ffi = @import("android_ffi.zig");
const config_parse = @import("config_parse.zig");
const fs_utils = @import("fs_utils.zig");
const options_mod = @import("options.zig");
const process = @import("process_supervisor.zig");
const tooling = @import("tooling.zig");
const types = @import("types.zig");

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

    const selected = if (options.skip_device_discovery)
        try resolvePreselectedAndroidDevice(arena, stderr, options.device_selector)
    else blk: {
        const devices = try android_discovery.discoverAndroidDevices(arena, io, stderr);
        const avds = try android_discovery.discoverAndroidAvds(arena, io);
        if (devices.len == 0 and avds.len == 0) {
            try stderr.writeAll("error: no Android devices and no AVD profiles found\n");
            return error.RunFailed;
        }
        const selected_target = try android_discovery.chooseAndroidTarget(
            arena,
            io,
            stderr,
            stdout,
            devices,
            avds,
            options.device_selector,
            options.non_interactive,
        );

        break :blk switch (selected_target) {
            .device => |device| device,
            .avd => |avd_name| blk_avd: {
                try stdout.print("starting AVD '{s}'...\n", .{avd_name});
                try stdout.flush();
                try android_discovery.startAvd(io, stderr, avd_name);
                const emulator = try android_discovery.waitForStartedEmulator(arena, io, stderr, devices, avd_name);
                break :blk_avd emulator;
            },
        };
    };

    try stdout.print("selected Android target: {s} [{s}]\n", .{ selected.model, selected.serial });
    try stdout.flush();

    const app_root_path = try app_root.resolveAppRoot(arena, io, options.project_dir);
    const android_ffi_artifact = try android_ffi.prepareAndroidFfiLibrary(
        arena,
        io,
        stderr,
        stdout,
        parent_environ_map,
        app_root_path,
        selected.serial,
    );
    try stdout.print("prepared Android FFI library for {s}: {s}\n", .{ android_ffi_artifact.abi, android_ffi_artifact.staged_path });
    try stdout.flush();

    std.Io.Dir.cwd().createDirPath(io, "/tmp/wizig-gradle-home") catch {};
    var gradle_env = try parent_environ_map.clone(arena);
    defer gradle_env.deinit();
    try gradle_env.put("GRADLE_USER_HOME", "/tmp/wizig-gradle-home");

    const gradle_wrapper_path = try fs_utils.joinPath(arena, options.project_dir, "gradlew");
    const gradle_wrapper_jar_path = try std.fmt.allocPrint(arena, "{s}{s}gradle{s}wrapper{s}gradle-wrapper.jar", .{ options.project_dir, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str });
    const has_wrapper_script = fs_utils.pathExists(io, gradle_wrapper_path);
    const has_wrapper_jar = fs_utils.pathExists(io, gradle_wrapper_jar_path);
    if (has_wrapper_script and !has_wrapper_jar) {
        try stdout.writeAll("warning: gradle wrapper jar is missing; falling back to system gradle\n");
        try stdout.flush();
    }
    const gradle_cmd: []const u8 = if (has_wrapper_script and has_wrapper_jar) "./gradlew" else "gradle";
    if (std.mem.eql(u8, gradle_cmd, "gradle") and !tooling.commandExists(arena, io, "gradle")) {
        try stderr.writeAll("error: gradle wrapper is incomplete and system gradle is not installed\n");
        return error.RunFailed;
    }

    const assemble_task = try std.fmt.allocPrint(arena, ":{s}:assembleDebug", .{options.module});
    const abi_property = try std.fmt.allocPrint(arena, "-Pandroid.injected.build.abi={s}", .{android_ffi_artifact.abi});

    try stdout.writeAll("building Android app...\n");
    try stdout.flush();
    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ gradle_cmd, "--no-daemon", abi_property, assemble_task },
        .cwd_path = options.project_dir,
        .environ_map = &gradle_env,
        .label = "build Android app",
    });

    const apk = try android_app_info.findDebugApk(arena, io, stderr, options.project_dir, options.module);

    var app_id = options.app_id;
    var activity = options.activity;
    if (app_id == null or activity == null) {
        const manifest_info = android_app_info.parseAndroidManifest(arena, io, options.project_dir, options.module) catch null;
        if (manifest_info) |info| {
            if (app_id == null) app_id = info.app_id;
            if (activity == null) activity = info.activity;
        }
    }
    if ((app_id == null or activity == null) and tooling.commandExists(arena, io, "aapt")) {
        const aapt_result = process.runCapture(arena, io, .{ .argv = &.{ "aapt", "dump", "badging", apk }, .label = "parse Android badging" }, .{}) catch |err| {
            try stderr.print("error: failed to run aapt to discover Android app id/activity: {s}\n", .{@errorName(err)});
            try stderr.writeAll("hint: pass --app-id and --activity manually\n");
            return error.RunFailed;
        };

        if (process.termIsSuccess(aapt_result.term)) {
            android_app_info.parseAaptBadging(aapt_result.stdout, &app_id, &activity);
        }
    }

    const app_id_value = app_id orelse {
        try stderr.writeAll("error: unable to determine Android application id (use --app-id)\n");
        return error.RunFailed;
    };
    const activity_value = activity orelse {
        try stderr.writeAll("error: unable to determine launch activity (use --activity)\n");
        return error.RunFailed;
    };
    const component = try config_parse.normalizeAndroidComponent(arena, app_id_value, activity_value);

    try process.runInheritChecked(io, stderr, .{ .argv = &.{ "adb", "-s", selected.serial, "install", "-r", "-t", apk }, .label = "install Android app" });
    _ = process.runCapture(arena, io, .{ .argv = &.{ "adb", "-s", selected.serial, "shell", "am", "force-stop", app_id_value }, .label = "force-stop Android app" }, .{}) catch {};

    if (debugger_mode == .jdb) {
        try process.runInheritChecked(io, stderr, .{ .argv = &.{ "adb", "-s", selected.serial, "shell", "am", "start", "-D", "-n", component }, .label = "launch Android app in debug-wait mode" });
    } else {
        try process.runInheritChecked(io, stderr, .{ .argv = &.{ "adb", "-s", selected.serial, "shell", "am", "start", "-n", component }, .label = "launch Android app" });
    }

    if (options.once) {
        try stdout.writeAll("run completed (--once)\n");
        try stdout.flush();
        return;
    }

    switch (debugger_mode) {
        .jdb => try android_debug.attachJdb(arena, io, stderr, stdout, selected.serial, app_id_value),
        .logcat => try streamAndroidLogs(arena, io, stderr, stdout, selected.serial, app_id_value, options.monitor_timeout_seconds),
        .none => {
            try stdout.writeAll("app launched without debugger\n");
            try stdout.flush();
        },
        else => {
            try stderr.writeAll("error: selected debugger is not valid for Android\n");
            return error.RunFailed;
        },
    }
}

fn resolvePreselectedAndroidDevice(
    arena: std.mem.Allocator,
    stderr: *Io.Writer,
    selector: ?[]const u8,
) !types.AndroidDevice {
    const serial = selector orelse {
        try stderr.writeAll("error: internal preselected Android run requires --device\n");
        return error.RunFailed;
    };
    if (std.mem.startsWith(u8, serial, "avd:")) {
        try stderr.writeAll("error: internal preselected Android run expects connected device serial\n");
        return error.RunFailed;
    }

    return .{ .serial = try arena.dupe(u8, serial), .model = try arena.dupe(u8, serial), .state = "device" };
}

fn streamAndroidLogs(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    serial: []const u8,
    app_id: []const u8,
    monitor_timeout_seconds: ?u64,
) !void {
    const liveness_probe = process.LivenessProbe{
        .spec = .{
            .argv = &.{ "adb", "-s", serial, "shell", "pidof", app_id },
            .label = "check Android app liveness",
        },
    };
    const watchdog: process.MonitorWatchdog = .{
        .timeout_seconds = monitor_timeout_seconds,
        .liveness_probe = liveness_probe,
    };

    const pid: ?u32 = android_debug.waitForAndroidPid(io, stderr, serial, app_id) catch |err| blk: {
        try stderr.print("warning: failed to determine Android pid for filtered logcat ({s}); falling back to full logcat\n", .{@errorName(err)});
        try stderr.flush();
        try stdout.writeAll("streaming logcat (Ctrl+C to stop)...\n");
        try stdout.flush();

        const monitor_result = try process.runInheritMonitored(
            arena,
            io,
            stderr,
            stdout,
            .{ .argv = &.{ "adb", "-s", serial, "logcat" }, .label = "stream Android logs" },
            watchdog,
        );
        try handleMonitorResult(stderr, stdout, monitor_result, "Android log stream");
        break :blk null;
    };

    if (pid) |android_pid| {
        var pid_buf: [24]u8 = undefined;
        const pid_text = try std.fmt.bufPrint(&pid_buf, "{d}", .{android_pid});
        try stdout.print("streaming logcat for pid {s} (Ctrl+C to stop)...\n", .{pid_text});
        try stdout.flush();
        const monitor_result = try process.runInheritMonitored(
            arena,
            io,
            stderr,
            stdout,
            .{
                .argv = &.{ "adb", "-s", serial, "logcat", "--pid", pid_text },
                .label = "stream Android logs",
            },
            watchdog,
        );
        try handleMonitorResult(stderr, stdout, monitor_result, "Android log stream");
    }
}

fn handleMonitorResult(
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    result: process.MonitoredTerm,
    label: []const u8,
) !void {
    switch (result.stop_reason) {
        .interrupted => {
            try stdout.print("{s} stopped by user\n", .{label});
            try stdout.flush();
            return;
        },
        .timeout => {
            try stdout.print("{s} stopped by monitor timeout\n", .{label});
            try stdout.flush();
            return;
        },
        .app_liveness_lost => {
            try stdout.print("{s} stopped because app exited\n", .{label});
            try stdout.flush();
            return;
        },
        .exited => {
            if (process.termIsSuccess(result.term)) {
                try stdout.print("{s} ended\n", .{label});
                try stdout.flush();
                return;
            }
            try stderr.writeAll("error: command failed for stream Android logs\n");
            try stderr.flush();
            return error.RunFailed;
        },
    }
}
