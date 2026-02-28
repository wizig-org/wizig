const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const Allocator = std.mem.Allocator;

pub const RunError = error{RunFailed};

const Platform = enum {
    ios,
    android,
};

const DebuggerMode = enum {
    auto,
    lldb,
    jdb,
    logcat,
    none,
};

const RunOptions = struct {
    platform: Platform,
    project_dir: []const u8,

    device_selector: ?[]const u8 = null,
    debugger: DebuggerMode = .auto,
    non_interactive: bool = false,
    once: bool = false,

    // iOS options.
    scheme: ?[]const u8 = null,
    bundle_id: ?[]const u8 = null,

    // Android options.
    module: []const u8 = "app",
    app_id: ?[]const u8 = null,
    activity: ?[]const u8 = null,
};

const IosDevice = struct {
    name: []const u8,
    udid: []const u8,
    runtime: []const u8,
    state: []const u8,
};

const AndroidDevice = struct {
    serial: []const u8,
    model: []const u8,
    state: []const u8,
};

const AndroidTarget = union(enum) {
    device: AndroidDevice,
    avd: []const u8,
};

pub fn run(
    arena: Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed_options = parseRunOptions(args, stderr) catch {
        try printUsage(stderr);
        try stderr.flush();
        return error.RunFailed;
    };
    const options = try normalizeRunOptions(arena, io, parsed_options);

    if (pathExists(io, "build.zig")) {
        try stdout.writeAll("building Zig artifacts...\n");
        try stdout.flush();
        try runInheritChecked(
            io,
            null,
            &.{ "zig", "build" },
            null,
            stderr,
            "build Zig artifacts",
        );
    } else {
        try stdout.writeAll("note: build.zig not found in current directory; skipping zig build\n");
        try stdout.flush();
    }

    switch (options.platform) {
        .ios => try runIos(arena, io, parent_environ_map, stderr, stdout, options),
        .android => try runAndroid(arena, io, parent_environ_map, stderr, stdout, options),
    }
}

pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Run:\n" ++
            "  ziggy run ios <project_dir> [options]\n" ++
            "  ziggy run android <project_dir> [options]\n" ++
            "\n" ++
            "Shared options:\n" ++
            "  --device <id_or_name>       Select target without prompt (Android AVD: avd:<name>)\n" ++
            "  --debugger <auto|lldb|jdb|logcat|none>\n" ++
            "  --non-interactive           Fail instead of prompting for selection\n" ++
            "  --once                      Launch and exit without attaching/streaming\n" ++
            "\n" ++
            "iOS options:\n" ++
            "  --scheme <scheme>\n" ++
            "  --bundle-id <bundle_identifier>\n" ++
            "\n" ++
            "Android options:\n" ++
            "  --module <gradle_module>    Defaults to app\n" ++
            "  --app-id <application_id>\n" ++
            "  --activity <activity_or_component>\n",
    );
}

fn parseRunOptions(args: []const []const u8, stderr: *Io.Writer) !RunOptions {
    if (args.len < 2) {
        try stderr.writeAll("error: run expects <ios|android> <project_dir> [options]\n");
        return error.RunFailed;
    }

    const platform = std.meta.stringToEnum(Platform, args[0]) orelse {
        try stderr.print("error: unknown platform '{s}', expected ios or android\n", .{args[0]});
        return error.RunFailed;
    };

    var options = RunOptions{
        .platform = platform,
        .project_dir = args[1],
    };

    var i: usize = 2;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--non-interactive")) {
            options.non_interactive = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--once")) {
            options.once = true;
            i += 1;
            continue;
        }

        if (i + 1 >= args.len) {
            try stderr.print("error: missing value for option '{s}'\n", .{arg});
            return error.RunFailed;
        }

        const value = args[i + 1];
        if (std.mem.eql(u8, arg, "--device")) {
            options.device_selector = value;
        } else if (std.mem.eql(u8, arg, "--debugger")) {
            options.debugger = std.meta.stringToEnum(DebuggerMode, value) orelse {
                try stderr.print("error: invalid debugger mode '{s}'\n", .{value});
                return error.RunFailed;
            };
        } else if (std.mem.eql(u8, arg, "--scheme")) {
            options.scheme = value;
        } else if (std.mem.eql(u8, arg, "--bundle-id")) {
            options.bundle_id = value;
        } else if (std.mem.eql(u8, arg, "--module")) {
            options.module = value;
        } else if (std.mem.eql(u8, arg, "--app-id")) {
            options.app_id = value;
        } else if (std.mem.eql(u8, arg, "--activity")) {
            options.activity = value;
        } else {
            try stderr.print("error: unknown run option '{s}'\n", .{arg});
            return error.RunFailed;
        }
        i += 2;
    }

    switch (options.platform) {
        .ios => {
            if (options.module.len != "app".len or !std.mem.eql(u8, options.module, "app")) {
                try stderr.writeAll("error: --module is Android-only\n");
                return error.RunFailed;
            }
            if (options.app_id != null or options.activity != null) {
                try stderr.writeAll("error: --app-id/--activity are Android-only\n");
                return error.RunFailed;
            }
        },
        .android => {
            if (options.scheme != null or options.bundle_id != null) {
                try stderr.writeAll("error: --scheme/--bundle-id are iOS-only\n");
                return error.RunFailed;
            }
        },
    }

    return options;
}

fn normalizeRunOptions(arena: Allocator, io: std.Io, options: RunOptions) !RunOptions {
    var normalized = options;
    if (!std.fs.path.isAbsolute(options.project_dir)) {
        const cwd = try std.process.currentPathAlloc(io, arena);
        normalized.project_dir = try std.fs.path.resolve(arena, &.{ cwd, options.project_dir });
    } else {
        normalized.project_dir = try arena.dupe(u8, options.project_dir);
    }
    return normalized;
}

fn runIos(
    arena: Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: RunOptions,
) !void {
    if (builtin.os.tag != .macos) {
        try stderr.writeAll("error: iOS run is only supported on macOS hosts\n");
        return error.RunFailed;
    }

    const debugger_mode = try resolveIosDebugger(arena, io, stderr, options.debugger);

    try maybeRegenerateIosProject(arena, io, stderr, stdout, options.project_dir);
    const xcode_project = try findXcodeProject(arena, io, stderr, options.project_dir);
    const scheme = options.scheme orelse inferSchemeFromProject(xcode_project) orelse {
        try stderr.writeAll("error: failed to infer iOS scheme, pass --scheme\n");
        return error.RunFailed;
    };

    const all_devices = try discoverIosDevices(arena, io, stderr);
    if (all_devices.len == 0) {
        try stderr.writeAll("error: no available iOS simulators found\n");
        return error.RunFailed;
    }
    const supported_ids = try discoverIosSupportedDestinationIds(
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
        try filterIosDevicesBySupportedIds(arena, all_devices, supported_ids);
    if (devices.len == 0) {
        try stderr.writeAll("error: no iOS simulators match xcodebuild destinations for this scheme\n");
        return error.RunFailed;
    }

    const selected = try chooseIosDevice(arena, io, stderr, stdout, devices, options.device_selector, options.non_interactive);

    try stdout.print(
        "selected iOS simulator: {s} [{s}] ({s}, {s})\n",
        .{ selected.name, selected.udid, selected.runtime, selected.state },
    );
    try stdout.flush();

    // Boot command can fail if simulator is already booted; this is not fatal.
    const boot_result = runCapture(
        arena,
        io,
        null,
        &.{ "xcrun", "simctl", "boot", selected.udid },
        null,
    ) catch null;
    if (boot_result) |result| {
        if (!termIsSuccess(result.term) and !containsAny(result.stderr, &.{
            "Unable to boot device in current state: Booted",
            "is already booted",
        })) {
            try stderr.writeAll("warning: simulator boot command reported an error; continuing\n");
            try stderr.flush();
        }
    }
    _ = runCapture(
        arena,
        io,
        null,
        &.{ "xcrun", "simctl", "bootstatus", selected.udid, "-b" },
        null,
    ) catch {};

    const destination = try std.fmt.allocPrint(arena, "id={s}", .{selected.udid});
    const derived_data = try std.fmt.allocPrint(arena, "/tmp/ziggy-derived-{s}", .{scheme});

    try stdout.writeAll("building iOS app...\n");
    try stdout.flush();
    try runInheritChecked(
        io,
        options.project_dir,
        &.{
            "xcodebuild",
            "-project",
            xcode_project,
            "-scheme",
            scheme,
            "-destination",
            destination,
            "-derivedDataPath",
            derived_data,
            "build",
        },
        null,
        stderr,
        "build iOS app",
    );

    const settings = try runCaptureChecked(
        arena,
        io,
        options.project_dir,
        &.{
            "xcodebuild",
            "-project",
            xcode_project,
            "-scheme",
            scheme,
            "-destination",
            destination,
            "-derivedDataPath",
            derived_data,
            "-showBuildSettings",
        },
        null,
        stderr,
        "read iOS build settings",
    );

    const target_build_dir = extractBuildSetting(settings.stdout, "TARGET_BUILD_DIR") orelse {
        try stderr.writeAll("error: failed to read TARGET_BUILD_DIR from xcodebuild settings\n");
        return error.RunFailed;
    };
    const wrapper_name = extractBuildSetting(settings.stdout, "WRAPPER_NAME") orelse {
        try stderr.writeAll("error: failed to read WRAPPER_NAME from xcodebuild settings\n");
        return error.RunFailed;
    };
    const bundle_id = options.bundle_id orelse (extractBuildSetting(settings.stdout, "PRODUCT_BUNDLE_IDENTIFIER") orelse {
        try stderr.writeAll("error: failed to read PRODUCT_BUNDLE_IDENTIFIER from xcodebuild settings; use --bundle-id\n");
        return error.RunFailed;
    });
    const app_path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ target_build_dir, wrapper_name });

    const workspace_root = try resolveZiggyWorkspaceRoot(arena, io, parent_environ_map, options.project_dir, stderr);
    const simulator_ffi_path = try buildIosSimulatorFfiLibrary(arena, io, stderr, workspace_root);
    const runtime_ffi_path = try bundleIosFfiLibraryForSimulator(arena, io, stderr, app_path, simulator_ffi_path);

    try runInheritChecked(
        io,
        null,
        &.{ "xcrun", "simctl", "install", selected.udid, app_path },
        null,
        stderr,
        "install iOS app",
    );

    _ = runCapture(
        arena,
        io,
        null,
        &.{ "xcrun", "simctl", "terminate", selected.udid, bundle_id },
        null,
    ) catch {};

    var launch_env = try parent_environ_map.clone(arena);
    defer launch_env.deinit();

    try launch_env.put("ZIGGY_FFI_LIB", runtime_ffi_path);
    try launch_env.put("SIMCTL_CHILD_ZIGGY_FFI_LIB", runtime_ffi_path);
    try launch_env.put("SIMCTL_CHILD_NSUnbufferedIO", "YES");
    try launch_env.put("SIMCTL_CHILD_CFLOG_FORCE_STDERR", "YES");
    try launch_env.put("SIMCTL_CHILD_OS_ACTIVITY_MODE", "disable");
    try stdout.print("configured iOS FFI path: {s}\n", .{runtime_ffi_path});
    try stdout.flush();

    if (debugger_mode == .none and !options.once) {
        try stdout.writeAll("launching iOS app with attached console (close app or Ctrl+C to stop)...\n");
        try stdout.flush();
        try launchIosAppWithConsoleRetry(
            arena,
            io,
            stderr,
            selected.udid,
            bundle_id,
            &launch_env,
        );
        return;
    }

    const launch = try launchIosAppWithRetry(arena, io, stderr, selected.udid, bundle_id, &launch_env);

    const pid = parseLaunchPid(launch.stdout) orelse {
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
            try stdout.writeAll("attaching lldb (exit lldb to stop ziggy run)...\n");
            try stdout.flush();
            try runInheritChecked(
                io,
                null,
                &.{ "lldb", "-o", attach_command, "-o", "continue" },
                null,
                stderr,
                "attach lldb to iOS app",
            );
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

fn runAndroid(
    arena: Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: RunOptions,
) !void {
    const debugger_mode = try resolveAndroidDebugger(arena, io, stderr, options.debugger);

    const devices = try discoverAndroidDevices(arena, io, stderr);
    const avds = try discoverAndroidAvds(arena, io);
    if (devices.len == 0 and avds.len == 0) {
        try stderr.writeAll("error: no Android devices and no AVD profiles found\n");
        return error.RunFailed;
    }
    const selected_target = try chooseAndroidTarget(
        arena,
        io,
        stderr,
        stdout,
        devices,
        avds,
        options.device_selector,
        options.non_interactive,
    );

    const selected = switch (selected_target) {
        .device => |device| device,
        .avd => |avd_name| blk: {
            try stdout.print("starting AVD '{s}'...\n", .{avd_name});
            try stdout.flush();
            try startAvd(io, stderr, avd_name);
            const emulator = try waitForStartedEmulator(arena, io, stderr, devices, avd_name);
            break :blk emulator;
        },
    };

    try stdout.print("selected Android target: {s} [{s}]\n", .{ selected.model, selected.serial });
    try stdout.flush();

    std.Io.Dir.cwd().createDirPath(io, "/tmp/ziggy-gradle-home") catch {};
    var gradle_env = try parent_environ_map.clone(arena);
    defer gradle_env.deinit();
    try gradle_env.put("GRADLE_USER_HOME", "/tmp/ziggy-gradle-home");

    const gradle_wrapper_path = try joinPath(arena, options.project_dir, "gradlew");
    const gradle_wrapper_jar_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}gradle{s}wrapper{s}gradle-wrapper.jar",
        .{
            options.project_dir,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
        },
    );
    const has_wrapper_script = pathExists(io, gradle_wrapper_path);
    const has_wrapper_jar = pathExists(io, gradle_wrapper_jar_path);
    if (has_wrapper_script and !has_wrapper_jar) {
        try stdout.writeAll("warning: gradle wrapper jar is missing; falling back to system gradle\n");
        try stdout.flush();
    }
    const gradle_cmd: []const u8 = if (has_wrapper_script and has_wrapper_jar) "./gradlew" else "gradle";
    const assemble_task = try std.fmt.allocPrint(arena, ":{s}:assembleDebug", .{options.module});

    try stdout.writeAll("building Android app...\n");
    try stdout.flush();
    try runInheritChecked(
        io,
        options.project_dir,
        &.{ gradle_cmd, "--no-daemon", assemble_task },
        &gradle_env,
        stderr,
        "build Android app",
    );

    const apk = try findDebugApk(arena, io, stderr, options.project_dir, options.module);

    var app_id = options.app_id;
    var activity = options.activity;
    if (app_id == null or activity == null) {
        const manifest_info = parseAndroidManifest(arena, io, options.project_dir, options.module) catch null;
        if (manifest_info) |info| {
            if (app_id == null) app_id = info.app_id;
            if (activity == null) activity = info.activity;
        }
    }
    if ((app_id == null or activity == null) and commandExists(arena, io, "aapt")) {
        const aapt_result = runCapture(
            arena,
            io,
            null,
            &.{ "aapt", "dump", "badging", apk },
            null,
        ) catch |err| {
            try stderr.print("error: failed to run aapt to discover Android app id/activity: {s}\n", .{@errorName(err)});
            try stderr.writeAll("hint: pass --app-id and --activity manually\n");
            return error.RunFailed;
        };

        if (termIsSuccess(aapt_result.term)) {
            parseAaptBadging(aapt_result.stdout, &app_id, &activity);
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
    const component = try normalizeAndroidComponent(arena, app_id_value, activity_value);

    try runInheritChecked(
        io,
        null,
        &.{ "adb", "-s", selected.serial, "install", "-r", apk },
        null,
        stderr,
        "install Android app",
    );

    _ = runCapture(
        arena,
        io,
        null,
        &.{ "adb", "-s", selected.serial, "shell", "am", "force-stop", app_id_value },
        null,
    ) catch {};

    if (debugger_mode == .jdb) {
        try runInheritChecked(
            io,
            null,
            &.{ "adb", "-s", selected.serial, "shell", "am", "start", "-D", "-n", component },
            null,
            stderr,
            "launch Android app in debug-wait mode",
        );
    } else {
        try runInheritChecked(
            io,
            null,
            &.{ "adb", "-s", selected.serial, "shell", "am", "start", "-n", component },
            null,
            stderr,
            "launch Android app",
        );
    }

    if (options.once) {
        try stdout.writeAll("run completed (--once)\n");
        try stdout.flush();
        return;
    }

    switch (debugger_mode) {
        .jdb => try attachJdb(arena, io, stderr, stdout, selected.serial, app_id_value),
        .logcat => {
            const pid: ?u32 = waitForAndroidPid(io, stderr, selected.serial, app_id_value) catch |err| blk: {
                try stderr.print(
                    "warning: failed to determine Android pid for filtered logcat ({s}); falling back to full logcat\n",
                    .{@errorName(err)},
                );
                try stderr.flush();
                try stdout.writeAll("streaming logcat (Ctrl+C to stop)...\n");
                try stdout.flush();
                const stream_term = try runInheritTerm(
                    io,
                    null,
                    &.{ "adb", "-s", selected.serial, "logcat" },
                    null,
                    stderr,
                    "stream Android logs",
                );
                if (termIsInterrupted(stream_term)) {
                    try stdout.writeAll("Android log stream stopped by user\n");
                    try stdout.flush();
                    break :blk null;
                }
                if (!termIsSuccess(stream_term)) {
                    try stderr.writeAll("error: command failed for stream Android logs\n");
                    try stderr.flush();
                    return error.RunFailed;
                }
                break :blk null;
            };
            if (pid) |android_pid| {
                var pid_buf: [24]u8 = undefined;
                const pid_text = try std.fmt.bufPrint(&pid_buf, "{d}", .{android_pid});
                try stdout.print("streaming logcat for pid {s} (Ctrl+C to stop)...\n", .{pid_text});
                try stdout.flush();
                const stream_term = try runInheritTerm(
                    io,
                    null,
                    &.{ "adb", "-s", selected.serial, "logcat", "--pid", pid_text },
                    null,
                    stderr,
                    "stream Android logs",
                );
                if (termIsInterrupted(stream_term)) {
                    try stdout.writeAll("Android log stream stopped by user\n");
                    try stdout.flush();
                    return;
                }
                if (!termIsSuccess(stream_term)) {
                    try stderr.writeAll("error: command failed for stream Android logs\n");
                    try stderr.flush();
                    return error.RunFailed;
                }
            }
        },
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

fn resolveIosDebugger(
    _: Allocator,
    _: std.Io,
    stderr: *Io.Writer,
    mode: DebuggerMode,
) !DebuggerMode {
    return switch (mode) {
        .auto => .none,
        .lldb, .none => mode,
        else => {
            try stderr.writeAll("error: iOS supports --debugger auto|lldb|none\n");
            return error.RunFailed;
        },
    };
}

fn resolveAndroidDebugger(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    mode: DebuggerMode,
) !DebuggerMode {
    return switch (mode) {
        .auto => .logcat,
        .jdb => blk: {
            if (!commandExists(arena, io, "jdb")) {
                try stderr.writeAll("error: jdb not found; use --debugger logcat|none or install JDK tools\n");
                return error.RunFailed;
            }
            break :blk .jdb;
        },
        .logcat, .none => mode,
        else => {
            try stderr.writeAll("error: Android supports --debugger auto|jdb|logcat|none\n");
            return error.RunFailed;
        },
    };
}

fn discoverIosDevices(arena: Allocator, io: std.Io, stderr: *Io.Writer) ![]IosDevice {
    const result = try runCaptureChecked(
        arena,
        io,
        null,
        &.{ "xcrun", "simctl", "list", "devices", "available", "--json" },
        null,
        stderr,
        "discover iOS simulators",
    );

    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, result.stdout, .{}) catch |err| {
        try stderr.print("error: failed to parse simctl JSON output: {s}\n", .{@errorName(err)});
        return error.RunFailed;
    };
    if (root != .object) {
        try stderr.writeAll("error: unexpected simctl JSON payload\n");
        return error.RunFailed;
    }
    const devices_value = root.object.get("devices") orelse {
        try stderr.writeAll("error: simctl JSON payload missing devices object\n");
        return error.RunFailed;
    };
    if (devices_value != .object) {
        try stderr.writeAll("error: simctl devices payload is not an object\n");
        return error.RunFailed;
    }

    var devices = std.ArrayList(IosDevice).empty;

    var runtime_it = devices_value.object.iterator();
    while (runtime_it.next()) |runtime_entry| {
        const runtime_key = runtime_entry.key_ptr.*;
        if (std.mem.indexOf(u8, runtime_key, "iOS-") == null) continue;

        const runtime_value = runtime_entry.value_ptr.*;
        if (runtime_value != .array) continue;

        const runtime_label = try runtimeLabelFromKey(arena, runtime_key);
        for (runtime_value.array.items) |device_value| {
            if (device_value != .object) continue;

            const name = jsonObjectString(device_value.object, "name") orelse continue;
            const udid = jsonObjectString(device_value.object, "udid") orelse continue;
            const state = jsonObjectString(device_value.object, "state") orelse "Unknown";
            const available = jsonObjectBool(device_value.object, "isAvailable") orelse true;
            if (!available) continue;

            try devices.append(arena, .{
                .name = try arena.dupe(u8, name),
                .udid = try arena.dupe(u8, udid),
                .runtime = runtime_label,
                .state = try arena.dupe(u8, state),
            });
        }
    }

    std.mem.sort(IosDevice, devices.items, {}, lessIosDevice);
    return devices.toOwnedSlice(arena);
}

fn discoverIosSupportedDestinationIds(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    xcode_project: []const u8,
    scheme: []const u8,
) ![]const []const u8 {
    const result = try runCaptureChecked(
        arena,
        io,
        project_dir,
        &.{ "xcodebuild", "-project", xcode_project, "-scheme", scheme, "-showdestinations" },
        null,
        stderr,
        "discover supported iOS destinations",
    );

    var ids = std.ArrayList([]const u8).empty;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (std.mem.indexOf(u8, line, "platform:iOS Simulator") == null) continue;
        const id = extractInlineField(line, "id:") orelse continue;
        if (std.mem.startsWith(u8, id, "dvtdevice-")) continue;
        try ids.append(arena, try arena.dupe(u8, id));
    }
    return ids.toOwnedSlice(arena);
}

fn filterIosDevicesBySupportedIds(
    arena: Allocator,
    devices: []const IosDevice,
    supported_ids: []const []const u8,
) ![]IosDevice {
    var filtered = std.ArrayList(IosDevice).empty;
    for (devices) |device| {
        if (!containsString(supported_ids, device.udid)) continue;
        try filtered.append(arena, device);
    }
    return filtered.toOwnedSlice(arena);
}

fn discoverAndroidDevices(arena: Allocator, io: std.Io, stderr: *Io.Writer) ![]AndroidDevice {
    const result = try runCaptureChecked(
        arena,
        io,
        null,
        &.{ "adb", "devices", "-l" },
        null,
        stderr,
        "discover Android devices",
    );

    var devices = try parseAndroidDevicesOutput(arena, result.stdout);
    std.mem.sort(AndroidDevice, devices.items, {}, lessAndroidDevice);
    return devices.toOwnedSlice(arena);
}

fn discoverAndroidAvds(arena: Allocator, io: std.Io) ![]const []const u8 {
    const result = runCapture(
        arena,
        io,
        null,
        &.{ "emulator", "-list-avds" },
        null,
    ) catch return arena.alloc([]const u8, 0);

    if (!termIsSuccess(result.term)) {
        return arena.alloc([]const u8, 0);
    }

    var avds = std.ArrayList([]const u8).empty;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        try avds.append(arena, try arena.dupe(u8, line));
    }
    std.mem.sort([]const u8, avds.items, {}, lessStringSlice);
    return avds.toOwnedSlice(arena);
}

fn chooseIosDevice(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    devices: []const IosDevice,
    selector: ?[]const u8,
    non_interactive: bool,
) !IosDevice {
    if (selector) |needle| {
        if (findIosDeviceBySelector(devices, needle)) |device| return device;
        try stderr.print("error: iOS simulator '{s}' not found\n", .{needle});
        return error.RunFailed;
    }

    if (devices.len == 1) return devices[0];
    if (non_interactive) {
        try stderr.writeAll("error: multiple iOS simulators found; pass --device\n");
        return error.RunFailed;
    }

    try stdout.writeAll("available iOS simulators:\n");
    for (devices, 0..) |device, idx| {
        try stdout.print(
            "  {d}. {s} [{s}] ({s}, {s})\n",
            .{ idx + 1, device.name, device.udid, device.runtime, device.state },
        );
    }
    try stdout.flush();

    const index = try promptSelection(arena, io, stderr, stdout, devices.len);
    return devices[index];
}

fn chooseAndroidTarget(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    devices: []const AndroidDevice,
    avds: []const []const u8,
    selector: ?[]const u8,
    non_interactive: bool,
) !AndroidTarget {
    if (selector) |needle| {
        if (findAndroidDeviceBySelector(devices, needle)) |device| return .{ .device = device };
        if (findAvdBySelector(avds, needle)) |avd_name| return .{ .avd = avd_name };
        try stderr.print("error: Android target '{s}' not found\n", .{needle});
        return error.RunFailed;
    }

    const total = devices.len + avds.len;
    if (total == 1) {
        if (devices.len == 1) return .{ .device = devices[0] };
        return .{ .avd = avds[0] };
    }
    if (non_interactive) {
        try stderr.writeAll("error: multiple Android targets found; pass --device\n");
        return error.RunFailed;
    }

    try stdout.writeAll("available Android targets:\n");
    for (devices, 0..) |device, idx| {
        try stdout.print("  {d}. {s} [{s}]\n", .{ idx + 1, device.model, device.serial });
    }
    for (avds, 0..) |avd_name, idx| {
        try stdout.print("  {d}. AVD {s}\n", .{ devices.len + idx + 1, avd_name });
    }
    try stdout.flush();

    const index = try promptSelection(arena, io, stderr, stdout, total);
    if (index < devices.len) return .{ .device = devices[index] };
    return .{ .avd = avds[index - devices.len] };
}

fn findDebugApk(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    module: []const u8,
) ![]const u8 {
    const apk_root = try std.fmt.allocPrint(
        arena,
        "{s}{s}{s}{s}build{s}outputs{s}apk",
        .{
            project_dir,
            std.fs.path.sep_str,
            module,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
        },
    );

    const result = try runCaptureChecked(
        arena,
        io,
        null,
        &.{ "find", apk_root, "-type", "f", "-name", "*-debug.apk" },
        null,
        stderr,
        "locate Android debug APK",
    );

    var first: ?[]const u8 = null;
    var preferred: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (first == null) first = line;
        if (std.mem.endsWith(u8, line, "/app-debug.apk") or std.mem.endsWith(u8, line, "\\app-debug.apk")) {
            preferred = line;
            break;
        }
    }

    const selected = preferred orelse first orelse {
        try stderr.writeAll("error: could not find a debug APK after build\n");
        return error.RunFailed;
    };
    return arena.dupe(u8, selected);
}

fn parseAaptBadging(output: []const u8, app_id: *?[]const u8, activity: *?[]const u8) void {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (app_id.* == null and std.mem.startsWith(u8, line, "package:")) {
            app_id.* = extractAfterMarker(line, "name='");
        }
        if (activity.* == null and std.mem.startsWith(u8, line, "launchable-activity:")) {
            activity.* = extractAfterMarker(line, "name='");
        }
    }
}

const AndroidManifestInfo = struct {
    app_id: ?[]const u8 = null,
    activity: ?[]const u8 = null,
};

fn parseAndroidManifest(
    arena: Allocator,
    io: std.Io,
    project_dir: []const u8,
    module: []const u8,
) !AndroidManifestInfo {
    const manifest_path = try std.fmt.allocPrint(
        arena,
        "{s}{s}{s}{s}src{s}main{s}AndroidManifest.xml",
        .{
            project_dir,
            std.fs.path.sep_str,
            module,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
            std.fs.path.sep_str,
        },
    );
    const content = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, arena, .limited(512 * 1024)) catch
        return error.RunFailed;

    var info = AndroidManifestInfo{};
    info.app_id = extractXmlAttribute(content, "manifest", "package");
    info.activity = extractXmlAttribute(content, "activity", "android:name");

    if (info.app_id == null) {
        const build_gradle_path = try std.fmt.allocPrint(
            arena,
            "{s}{s}{s}{s}build.gradle.kts",
            .{
                project_dir,
                std.fs.path.sep_str,
                module,
                std.fs.path.sep_str,
            },
        );
        const gradle_content = std.Io.Dir.cwd().readFileAlloc(io, build_gradle_path, arena, .limited(512 * 1024)) catch null;
        if (gradle_content) |build_contents| {
            info.app_id = extractGradleStringValue(build_contents, "applicationId") orelse extractGradleStringValue(build_contents, "namespace");
        }
    }
    return info;
}

fn normalizeAndroidComponent(arena: Allocator, app_id: []const u8, activity: []const u8) ![]const u8 {
    if (std.mem.containsAtLeast(u8, activity, 1, "/")) {
        return arena.dupe(u8, activity);
    }
    if (std.mem.startsWith(u8, activity, ".")) {
        return std.fmt.allocPrint(arena, "{s}/{s}", .{ app_id, activity });
    }
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ app_id, activity });
}

fn attachJdb(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    serial: []const u8,
    app_id: []const u8,
) !void {
    try stdout.writeAll("waiting for Android debug process...\n");
    try stdout.flush();

    const pid = try waitForAndroidPid(io, stderr, serial, app_id);
    try waitForJdwpPid(io, stderr, serial, pid);
    const port = try setupAdbForward(io, stderr, serial, pid);

    var forward_buf: [24]u8 = undefined;
    const forward_name = try std.fmt.bufPrint(&forward_buf, "tcp:{d}", .{port});
    defer {
        _ = runCapture(
            arena,
            io,
            null,
            &.{ "adb", "-s", serial, "forward", "--remove", forward_name },
            null,
        ) catch {};
    }

    var attach_buf: [32]u8 = undefined;
    const attach_target = try std.fmt.bufPrint(&attach_buf, "localhost:{d}", .{port});

    try stdout.print("attaching jdb to pid {d} on {s} (type `run` in jdb if app is waiting)...\n", .{ pid, attach_target });
    try stdout.flush();
    try runInheritChecked(
        io,
        null,
        &.{ "jdb", "-attach", attach_target },
        null,
        stderr,
        "attach jdb",
    );
}

fn waitForAndroidPid(
    io: std.Io,
    stderr: *Io.Writer,
    serial: []const u8,
    app_id: []const u8,
) !u32 {
    var attempt: usize = 0;
    while (attempt < 120) : (attempt += 1) {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();

        const result = runCapture(
            scratch,
            io,
            null,
            &.{ "adb", "-s", serial, "shell", "pidof", app_id },
            null,
        ) catch {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        };
        if (!termIsSuccess(result.term)) {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        }
        if (parseFirstIntToken(u32, result.stdout)) |pid| return pid;
        std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
    }

    try stderr.writeAll("error: timed out waiting for Android app PID\n");
    return error.RunFailed;
}

fn waitForJdwpPid(
    io: std.Io,
    stderr: *Io.Writer,
    serial: []const u8,
    pid: u32,
) !void {
    var attempt: usize = 0;
    while (attempt < 120) : (attempt += 1) {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();

        const result = runCapture(
            scratch,
            io,
            null,
            &.{ "adb", "-s", serial, "jdwp" },
            null,
        ) catch {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        };
        if (termIsSuccess(result.term) and hasPidLine(result.stdout, pid)) return;
        std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
    }
    try stderr.writeAll("error: timed out waiting for JDWP endpoint\n");
    return error.RunFailed;
}

fn setupAdbForward(
    io: std.Io,
    stderr: *Io.Writer,
    serial: []const u8,
    pid: u32,
) !u16 {
    var port: u16 = 8700;
    while (port < 8800) : (port += 1) {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();

        var tcp_buf: [24]u8 = undefined;
        var jdwp_buf: [24]u8 = undefined;
        const tcp_name = try std.fmt.bufPrint(&tcp_buf, "tcp:{d}", .{port});
        const jdwp_name = try std.fmt.bufPrint(&jdwp_buf, "jdwp:{d}", .{pid});

        const result = runCapture(
            scratch,
            io,
            null,
            &.{ "adb", "-s", serial, "forward", tcp_name, jdwp_name },
            null,
        ) catch continue;
        if (termIsSuccess(result.term)) return port;
    }

    try stderr.writeAll("error: failed to reserve local JDWP forwarding port\n");
    return error.RunFailed;
}

fn findXcodeProject(arena: Allocator, io: std.Io, stderr: *Io.Writer, project_dir: []const u8) ![]const u8 {
    const result = try runCaptureChecked(
        arena,
        io,
        null,
        &.{ "find", project_dir, "-maxdepth", "1", "-type", "d", "-name", "*.xcodeproj" },
        null,
        stderr,
        "locate Xcode project",
    );

    var first: ?[]const u8 = null;
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        count += 1;
        if (first == null) first = line;
    }

    if (count == 0) {
        try stderr.writeAll("error: no .xcodeproj found in project directory\n");
        return error.RunFailed;
    }
    if (count > 1) {
        try stderr.writeAll("warning: multiple .xcodeproj directories found; using first match\n");
        try stderr.flush();
    }

    return arena.dupe(u8, first.?);
}

fn maybeRegenerateIosProject(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_dir: []const u8,
) !void {
    const project_spec = try joinPath(arena, project_dir, "project.yml");
    if (!pathExists(io, project_spec)) return;

    if (!commandExists(arena, io, "xcodegen")) {
        try stderr.writeAll("warning: xcodegen not found; skipping iOS project regeneration\n");
        try stderr.flush();
        return;
    }

    try stdout.writeAll("regenerating iOS project...\n");
    try stdout.flush();
    try runInheritChecked(
        io,
        project_dir,
        &.{ "xcodegen", "generate" },
        null,
        stderr,
        "generate iOS project",
    );
}

fn inferSchemeFromProject(project_path: []const u8) ?[]const u8 {
    const base = std.fs.path.basename(project_path);
    if (!std.mem.endsWith(u8, base, ".xcodeproj")) return null;
    return base[0 .. base.len - ".xcodeproj".len];
}

fn runtimeLabelFromKey(arena: Allocator, runtime_key: []const u8) ![]const u8 {
    const marker = "SimRuntime.";
    const start = std.mem.indexOf(u8, runtime_key, marker) orelse return arena.dupe(u8, runtime_key);
    const suffix = runtime_key[start + marker.len ..];
    const out = try arena.dupe(u8, suffix);
    for (out) |*char| {
        if (char.* == '-') char.* = '.';
    }
    return out;
}

fn jsonObjectString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn jsonObjectBool(object: std.json.ObjectMap, key: []const u8) ?bool {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .bool => |v| v,
        else => null,
    };
}

fn extractBuildSetting(settings: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, settings, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len <= key.len + 3) continue;
        if (!std.mem.startsWith(u8, line, key)) continue;
        if (line[key.len] != ' ') continue;
        if (line[key.len + 1] != '=') continue;
        if (line[key.len + 2] != ' ') continue;
        return line[key.len + 3 ..];
    }
    return null;
}

fn parseLaunchPid(output: []const u8) ?u32 {
    return parseLastIntToken(u32, output);
}

fn launchIosAppWithRetry(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    udid: []const u8,
    bundle_id: []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !std.process.RunResult {
    var attempt: usize = 0;
    while (attempt < 5) : (attempt += 1) {
        const result = runCapture(
            arena,
            io,
            null,
            &.{ "xcrun", "simctl", "launch", udid, bundle_id },
            environ_map,
        ) catch |err| {
            try stderr.print("error: failed to spawn command for launch iOS app: {s}\n", .{@errorName(err)});
            try stderr.flush();
            return error.RunFailed;
        };

        const pid = parseLaunchPid(result.stdout);
        if (termIsSuccess(result.term) and pid != null) {
            return result;
        }

        const can_retry = if (termIsSuccess(result.term))
            pid == null
        else
            isTransientIosLaunchFailure(result.stdout, result.stderr);

        if (!can_retry or attempt + 1 >= 5) {
            try stderr.writeAll("error: command failed for launch iOS app: xcrun\n");
            if (result.stdout.len > 0) {
                try stderr.print("{s}\n", .{result.stdout});
            }
            if (result.stderr.len > 0) {
                try stderr.print("{s}\n", .{result.stderr});
            }
            try stderr.flush();
            return error.RunFailed;
        }

        try stderr.print("warning: transient iOS launch failure (attempt {d}/5), retrying...\n", .{attempt + 1});
        try stderr.flush();
        _ = runCapture(
            arena,
            io,
            null,
            &.{ "xcrun", "simctl", "terminate", udid, bundle_id },
            null,
        ) catch {};
        _ = runCapture(
            arena,
            io,
            null,
            &.{ "xcrun", "simctl", "bootstatus", udid, "-b" },
            null,
        ) catch {};
        std.Io.sleep(io, .fromMilliseconds(700), .awake) catch {};
    }

    return error.RunFailed;
}

fn launchIosAppWithConsoleRetry(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    udid: []const u8,
    bundle_id: []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !void {
    var attempt: usize = 0;
    while (attempt < 5) : (attempt += 1) {
        const term = try runInheritTerm(
            io,
            null,
            &.{
                "xcrun",
                "simctl",
                "launch",
                "--terminate-running-process",
                "--console-pty",
                udid,
                bundle_id,
            },
            environ_map,
            stderr,
            "launch iOS app with console",
        );
        if (termIsSuccess(term) or termIsInterrupted(term)) {
            return;
        }

        if (attempt + 1 >= 5) {
            try stderr.writeAll("error: command failed for launch iOS app with console\n");
            try stderr.flush();
            return error.RunFailed;
        }

        try stderr.print("warning: transient iOS console launch failure (attempt {d}/5), retrying...\n", .{attempt + 1});
        try stderr.flush();
        _ = runCapture(
            arena,
            io,
            null,
            &.{ "xcrun", "simctl", "terminate", udid, bundle_id },
            null,
        ) catch {};
        _ = runCapture(
            arena,
            io,
            null,
            &.{ "xcrun", "simctl", "bootstatus", udid, "-b" },
            null,
        ) catch {};
        std.Io.sleep(io, .fromMilliseconds(700), .awake) catch {};
    }

    return error.RunFailed;
}

fn resolveZiggyWorkspaceRoot(
    arena: Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    project_dir: []const u8,
    stderr: *Io.Writer,
) ![]const u8 {
    if (try resolveAppLocalRuntimeRoot(arena, io, project_dir)) |runtime_root| {
        return runtime_root;
    }

    if (parent_environ_map.get("ZIGGY_SDK_ROOT")) |raw_root| {
        const resolved = if (std.fs.path.isAbsolute(raw_root))
            try arena.dupe(u8, raw_root)
        else blk: {
            const cwd = try std.process.currentPathAlloc(io, arena);
            break :blk try std.fs.path.resolve(arena, &.{ cwd, raw_root });
        };
        const marker = try std.fmt.allocPrint(
            arena,
            "{s}{s}ffi{s}src{s}root.zig",
            .{ resolved, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
        );
        if (pathExists(io, marker)) return resolved;
    }

    if (try extractZiggyWorkspaceFromProjectYml(arena, io, project_dir)) |root| {
        return root;
    }

    const cwd = try std.process.currentPathAlloc(io, arena);
    const cwd_marker = try std.fmt.allocPrint(
        arena,
        "{s}{s}ffi{s}src{s}root.zig",
        .{ cwd, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    );
    if (pathExists(io, cwd_marker)) return cwd;

    try stderr.writeAll(
        "error: unable to resolve Ziggy runtime root; expected app-local .ziggy/runtime or set ZIGGY_SDK_ROOT\n",
    );
    return error.RunFailed;
}

fn resolveAppLocalRuntimeRoot(
    arena: Allocator,
    io: std.Io,
    project_dir: []const u8,
) !?[]const u8 {
    const direct = try std.fs.path.resolve(arena, &.{ project_dir, ".ziggy", "runtime" });
    if (runtimeRootLooksValid(arena, io, direct)) return direct;

    const parent = std.fs.path.dirname(project_dir) orelse return null;
    const parent_candidate = try std.fs.path.resolve(arena, &.{ parent, ".ziggy", "runtime" });
    if (runtimeRootLooksValid(arena, io, parent_candidate)) return parent_candidate;

    return null;
}

fn runtimeRootLooksValid(
    arena: Allocator,
    io: std.Io,
    root: []const u8,
) bool {
    const marker_core = std.fmt.allocPrint(
        arena,
        "{s}{s}core{s}src{s}root.zig",
        .{ root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    ) catch return false;
    const marker_ffi = std.fmt.allocPrint(
        arena,
        "{s}{s}ffi{s}src{s}root.zig",
        .{ root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
    ) catch return false;
    return pathExists(io, marker_core) and pathExists(io, marker_ffi);
}

fn extractZiggyWorkspaceFromProjectYml(
    arena: Allocator,
    io: std.Io,
    project_dir: []const u8,
) !?[]const u8 {
    const project_yml_path = try std.fmt.allocPrint(arena, "{s}{s}project.yml", .{ project_dir, std.fs.path.sep_str });
    const content = std.Io.Dir.cwd().readFileAlloc(io, project_yml_path, arena, .limited(512 * 1024)) catch return null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, "path:")) continue;

        const raw_value = std.mem.trim(u8, line["path:".len..], " \t\r");
        const value = trimOptionalQuotes(raw_value);
        if (value.len == 0) continue;

        const sdk_path = if (std.fs.path.isAbsolute(value))
            try arena.dupe(u8, value)
        else
            try std.fs.path.resolve(arena, &.{ project_dir, value });

        const sdk_norm = try arena.dupe(u8, sdk_path);
        for (sdk_norm) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }

        const suffix = "/sdk/ios";
        if (!std.mem.endsWith(u8, sdk_norm, suffix)) continue;
        if (sdk_norm.len <= suffix.len) continue;

        const root = try arena.dupe(u8, sdk_path[0 .. sdk_path.len - suffix.len]);
        const marker = try std.fmt.allocPrint(
            arena,
            "{s}{s}ffi{s}src{s}root.zig",
            .{ root, std.fs.path.sep_str, std.fs.path.sep_str, std.fs.path.sep_str },
        );
        if (pathExists(io, marker)) return root;
    }

    return null;
}

fn trimOptionalQuotes(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return value[1 .. value.len - 1];
    }
    if (value.len >= 2 and value[0] == '\'' and value[value.len - 1] == '\'') {
        return value[1 .. value.len - 1];
    }
    return value;
}

fn buildIosSimulatorFfiLibrary(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    workspace_root: []const u8,
) ![]const u8 {
    const sdk = try runCaptureChecked(
        arena,
        io,
        null,
        &.{ "xcrun", "--sdk", "iphonesimulator", "--show-sdk-path" },
        null,
        stderr,
        "resolve iOS simulator SDK path",
    );
    const sdk_path = std.mem.trim(u8, sdk.stdout, " \t\r\n");
    if (sdk_path.len == 0) {
        try stderr.writeAll("error: xcrun returned an empty iOS simulator SDK path\n");
        return error.RunFailed;
    }

    const out_dir = "/tmp/ziggy-ffi-iossim";
    std.Io.Dir.cwd().createDirPath(io, out_dir) catch {};

    const out_path = try std.fmt.allocPrint(arena, "{s}{s}ziggyffi", .{ out_dir, std.fs.path.sep_str });
    const emit_arg = try std.fmt.allocPrint(arena, "-femit-bin={s}", .{out_path});

    _ = try runCaptureChecked(
        arena,
        io,
        workspace_root,
        &.{
            "zig",
            "build-lib",
            "-OReleaseFast",
            "-target",
            "aarch64-ios-simulator",
            "--dep",
            "ziggy_core",
            "-Mroot=ffi/src/root.zig",
            "-Mziggy_core=core/src/root.zig",
            "--name",
            "ziggyffi",
            "-dynamic",
            "-install_name",
            "@rpath/libziggyffi.dylib",
            "--sysroot",
            sdk_path,
            "-L/usr/lib",
            "-F/System/Library/Frameworks",
            "-lc",
            emit_arg,
        },
        null,
        stderr,
        "build iOS simulator Ziggy FFI library",
    );

    return out_path;
}

fn bundleIosFfiLibraryForSimulator(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) ![]const u8 {
    const frameworks_dir = try std.fmt.allocPrint(arena, "{s}{s}Frameworks", .{ app_path, std.fs.path.sep_str });
    std.Io.Dir.cwd().createDirPath(io, frameworks_dir) catch {};

    const app_bundle_ffi = try std.fmt.allocPrint(arena, "{s}{s}ziggyffi", .{ app_path, std.fs.path.sep_str });
    const frameworks_ffi = try std.fmt.allocPrint(arena, "{s}{s}ziggyffi", .{ frameworks_dir, std.fs.path.sep_str });

    _ = try runCaptureChecked(
        arena,
        io,
        null,
        &.{ "cp", host_ffi_path, app_bundle_ffi },
        null,
        stderr,
        "copy Ziggy FFI into iOS app bundle",
    );
    _ = try runCaptureChecked(
        arena,
        io,
        null,
        &.{ "cp", host_ffi_path, frameworks_ffi },
        null,
        stderr,
        "copy Ziggy FFI into iOS app Frameworks",
    );

    return "@executable_path/Frameworks/ziggyffi";
}

fn resolveIosFfiLibraryPath(
    arena: Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
) !?[]const u8 {
    if (parent_environ_map.get("ZIGGY_FFI_LIB")) |raw_path| {
        if (std.fs.path.isAbsolute(raw_path)) {
            if (pathExists(io, raw_path)) return try arena.dupe(u8, raw_path);
        } else {
            const cwd = try std.process.currentPathAlloc(io, arena);
            const resolved = try std.fs.path.resolve(arena, &.{ cwd, raw_path });
            if (pathExists(io, resolved)) return resolved;
        }
    }

    const cwd = try std.process.currentPathAlloc(io, arena);
    const guessed = try std.fs.path.resolve(arena, &.{ cwd, "zig-out", "lib", "libziggyffi.dylib" });
    if (pathExists(io, guessed)) return guessed;
    return null;
}

fn isTransientIosLaunchFailure(stdout: []const u8, stderr: []const u8) bool {
    return containsAny(stdout, &.{
        "did not return a process handle nor launch error",
        "No such process",
        "Operation timed out",
    }) or containsAny(stderr, &.{
        "did not return a process handle nor launch error",
        "No such process",
        "Operation timed out",
    });
}

fn promptSelection(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    option_count: usize,
) !usize {
    var attempts: usize = 0;
    while (attempts < 8) : (attempts += 1) {
        try stdout.print("select target [1-{d}]: ", .{option_count});
        try stdout.flush();

        const line = readTrimmedLine(arena, io) catch |err| switch (err) {
            error.EndOfStream => {
                try stderr.writeAll("error: no input received\n");
                return error.RunFailed;
            },
            else => |e| return e,
        };
        const parsed = std.fmt.parseInt(usize, line, 10) catch {
            try stderr.print("error: invalid selection '{s}'\n", .{line});
            try stderr.flush();
            continue;
        };
        if (parsed >= 1 and parsed <= option_count) {
            return parsed - 1;
        }
        try stderr.print("error: selection must be between 1 and {d}\n", .{option_count});
        try stderr.flush();
    }

    return error.RunFailed;
}

fn readTrimmedLine(arena: Allocator, io: std.Io) ![]const u8 {
    var stdin_buffer: [256]u8 = undefined;
    var file_reader = std.Io.File.stdin().reader(io, &stdin_buffer);

    const raw_line = file_reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => blk: {
            if (file_reader.interface.bufferedLen() == 0) return error.EndOfStream;
            break :blk file_reader.interface.buffered();
        },
        else => |e| return e,
    };

    const trimmed = std.mem.trim(u8, raw_line, " \t\r");
    return arena.dupe(u8, trimmed);
}

fn findIosDeviceBySelector(devices: []const IosDevice, selector: []const u8) ?IosDevice {
    for (devices) |device| {
        if (std.mem.eql(u8, device.udid, selector)) return device;
        if (std.ascii.eqlIgnoreCase(device.name, selector)) return device;
    }
    return null;
}

fn findAndroidDeviceBySelector(devices: []const AndroidDevice, selector: []const u8) ?AndroidDevice {
    for (devices) |device| {
        if (std.mem.eql(u8, device.serial, selector)) return device;
        if (std.ascii.eqlIgnoreCase(device.model, selector)) return device;
    }
    return null;
}

fn findAvdBySelector(avds: []const []const u8, selector: []const u8) ?[]const u8 {
    const normalized = if (std.mem.startsWith(u8, selector, "avd:")) selector["avd:".len..] else selector;
    for (avds) |avd_name| {
        if (std.mem.eql(u8, avd_name, normalized)) return avd_name;
        if (std.ascii.eqlIgnoreCase(avd_name, normalized)) return avd_name;
    }
    return null;
}

fn parseAndroidDevicesOutput(arena: Allocator, output: []const u8) !std.ArrayList(AndroidDevice) {
    var devices = std.ArrayList(AndroidDevice).empty;
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "List of devices attached")) continue;
        if (line[0] == '*') continue;

        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const serial = tokens.next() orelse continue;
        const state = tokens.next() orelse continue;
        if (!std.mem.eql(u8, state, "device")) continue;

        var model_name: ?[]const u8 = null;
        while (tokens.next()) |token| {
            if (std.mem.startsWith(u8, token, "model:")) {
                model_name = token["model:".len..];
            }
        }

        const model = model_name orelse serial;
        try devices.append(arena, .{
            .serial = try arena.dupe(u8, serial),
            .model = try arena.dupe(u8, model),
            .state = try arena.dupe(u8, state),
        });
    }
    return devices;
}

fn startAvd(io: std.Io, stderr: *Io.Writer, avd_name: []const u8) !void {
    _ = std.process.spawn(io, .{
        .argv = &.{ "emulator", "-avd", avd_name },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch |err| {
        try stderr.print("error: failed to start emulator '{s}': {s}\n", .{ avd_name, @errorName(err) });
        return error.RunFailed;
    };
}

fn waitForStartedEmulator(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    existing_devices: []const AndroidDevice,
    avd_name: []const u8,
) !AndroidDevice {
    var attempt: usize = 0;
    while (attempt < 240) : (attempt += 1) {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();

        const result = runCapture(
            scratch,
            io,
            null,
            &.{ "adb", "devices", "-l" },
            null,
        ) catch {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        };
        if (!termIsSuccess(result.term)) {
            std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
            continue;
        }

        var devices = try parseAndroidDevicesOutput(scratch, result.stdout);
        for (devices.items) |device| {
            if (!std.mem.startsWith(u8, device.serial, "emulator-")) continue;
            if (containsAndroidSerial(existing_devices, device.serial)) continue;
            return cloneAndroidDevice(arena, device);
        }
        if (existing_devices.len == 0 and devices.items.len == 1 and std.mem.startsWith(u8, devices.items[0].serial, "emulator-")) {
            return cloneAndroidDevice(arena, devices.items[0]);
        }
        std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
    }

    try stderr.print("error: timed out waiting for AVD '{s}' to appear in adb devices\n", .{avd_name});
    return error.RunFailed;
}

fn containsAndroidSerial(devices: []const AndroidDevice, serial: []const u8) bool {
    for (devices) |device| {
        if (std.mem.eql(u8, device.serial, serial)) return true;
    }
    return false;
}

fn cloneAndroidDevice(allocator: Allocator, device: AndroidDevice) !AndroidDevice {
    return .{
        .serial = try allocator.dupe(u8, device.serial),
        .model = try allocator.dupe(u8, device.model),
        .state = try allocator.dupe(u8, device.state),
    };
}

fn lessIosDevice(_: void, a: IosDevice, b: IosDevice) bool {
    const a_booted = std.mem.eql(u8, a.state, "Booted");
    const b_booted = std.mem.eql(u8, b.state, "Booted");
    if (a_booted != b_booted) return a_booted;

    if (!std.mem.eql(u8, a.runtime, b.runtime)) {
        return std.mem.lessThan(u8, a.runtime, b.runtime);
    }
    return std.mem.lessThan(u8, a.name, b.name);
}

fn lessAndroidDevice(_: void, a: AndroidDevice, b: AndroidDevice) bool {
    return std.mem.lessThan(u8, a.serial, b.serial);
}

fn lessStringSlice(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn parseFirstIntToken(comptime T: type, input: []const u8) ?T {
    var it = std.mem.tokenizeAny(u8, input, " \t\r\n");
    while (it.next()) |token| {
        if (std.fmt.parseInt(T, token, 10)) |value| return value else |_| continue;
    }
    return null;
}

fn parseLastIntToken(comptime T: type, input: []const u8) ?T {
    var it = std.mem.tokenizeAny(u8, input, " \t\r\n:");
    var last: ?T = null;
    while (it.next()) |token| {
        const value = std.fmt.parseInt(T, token, 10) catch continue;
        last = value;
    }
    return last;
}

fn hasPidLine(output: []const u8, pid: u32) bool {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        if (std.fmt.parseInt(u32, line, 10)) |parsed| {
            if (parsed == pid) return true;
        } else |_| {}
    }
    return false;
}

fn extractAfterMarker(line: []const u8, marker: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, marker) orelse return null;
    const rest = line[start + marker.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '\'') orelse return null;
    return rest[0..end];
}

fn extractInlineField(line: []const u8, field_prefix: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, field_prefix) orelse return null;
    var rest = line[start + field_prefix.len ..];
    rest = std.mem.trim(u8, rest, " \t");
    if (rest.len == 0) return null;

    const comma = std.mem.indexOfScalar(u8, rest, ',');
    const brace = std.mem.indexOfScalar(u8, rest, '}');
    const end_idx = switch (comma != null and brace != null) {
        true => @min(comma.?, brace.?),
        false => comma orelse brace orelse rest.len,
    };
    return std.mem.trim(u8, rest[0..end_idx], " \t\r");
}

fn containsString(items: []const []const u8, value: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, value)) return true;
    }
    return false;
}

fn extractXmlAttribute(xml: []const u8, tag_name: []const u8, attr_name: []const u8) ?[]const u8 {
    var cursor: usize = 0;
    while (cursor < xml.len) {
        const open = std.mem.indexOfPos(u8, xml, cursor, "<") orelse return null;
        const close = std.mem.indexOfPos(u8, xml, open, ">") orelse return null;
        const element = xml[open + 1 .. close];
        cursor = close + 1;

        if (element.len == 0 or element[0] == '/' or element[0] == '!' or element[0] == '?') continue;
        if (!std.mem.startsWith(u8, element, tag_name)) continue;
        if (element.len > tag_name.len and !std.ascii.isWhitespace(element[tag_name.len])) continue;

        var attr_it = std.mem.splitAny(u8, element, " \t\r\n");
        _ = attr_it.next();
        while (attr_it.next()) |token| {
            if (!std.mem.startsWith(u8, token, attr_name)) continue;
            if (token.len <= attr_name.len + 2) continue;
            if (token[attr_name.len] != '=') continue;
            if (token[attr_name.len + 1] != '"') continue;
            const rest = token[attr_name.len + 2 ..];
            const quote_end = std.mem.indexOfScalar(u8, rest, '"') orelse continue;
            return rest[0..quote_end];
        }
    }
    return null;
}

fn extractGradleStringValue(content: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, key)) continue;
        const quote_start = std.mem.indexOfScalar(u8, line, '"') orelse continue;
        const rest = line[quote_start + 1 ..];
        const quote_end = std.mem.indexOfScalar(u8, rest, '"') orelse continue;
        return rest[0..quote_end];
    }
    return null;
}

fn joinPath(allocator: Allocator, base: []const u8, name: []const u8) ![]u8 {
    if (std.mem.eql(u8, base, ".")) {
        return allocator.dupe(u8, name);
    }
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ base, std.fs.path.sep_str, name });
}

fn pathExists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

fn commandExists(arena: Allocator, io: std.Io, command_name: []const u8) bool {
    const result = runCapture(
        arena,
        io,
        null,
        &.{ "which", command_name },
        null,
    ) catch return false;
    return termIsSuccess(result.term) and std.mem.trim(u8, result.stdout, " \t\r\n").len > 0;
}

fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) != null) return true;
    }
    return false;
}

fn childCwd(path: ?[]const u8) std.process.Child.Cwd {
    return if (path) |p| .{ .path = p } else .inherit;
}

fn runCapture(
    arena: Allocator,
    io: std.Io,
    cwd_path: ?[]const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !std.process.RunResult {
    return std.process.run(arena, io, .{
        .argv = argv,
        .cwd = childCwd(cwd_path),
        .environ_map = environ_map,
        .stdout_limit = .limited(8 * 1024 * 1024),
        .stderr_limit = .limited(8 * 1024 * 1024),
    });
}

fn runCaptureChecked(
    arena: Allocator,
    io: std.Io,
    cwd_path: ?[]const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
    stderr: *Io.Writer,
    label: []const u8,
) !std.process.RunResult {
    const result = runCapture(arena, io, cwd_path, argv, environ_map) catch |err| {
        try stderr.print("error: failed to spawn command for {s}: {s}\n", .{ label, @errorName(err) });
        try stderr.flush();
        return error.RunFailed;
    };
    if (!termIsSuccess(result.term)) {
        try stderr.print("error: command failed for {s}: {s}\n", .{ label, argv[0] });
        if (result.stdout.len > 0) {
            try stderr.print("{s}\n", .{result.stdout});
        }
        if (result.stderr.len > 0) {
            try stderr.print("{s}\n", .{result.stderr});
        }
        try stderr.flush();
        return error.RunFailed;
    }
    return result;
}

fn runInheritChecked(
    io: std.Io,
    cwd_path: ?[]const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
    stderr: *Io.Writer,
    label: []const u8,
) !void {
    const term = try runInheritTerm(io, cwd_path, argv, environ_map, stderr, label);
    if (!termIsSuccess(term)) {
        try stderr.print("error: command failed for {s}\n", .{label});
        try stderr.flush();
        return error.RunFailed;
    }
}

fn runInheritTerm(
    io: std.Io,
    cwd_path: ?[]const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
    stderr: *Io.Writer,
    label: []const u8,
) !std.process.Child.Term {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .cwd = childCwd(cwd_path),
        .environ_map = environ_map,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        try stderr.print("error: failed to spawn command for {s}: {s}\n", .{ label, @errorName(err) });
        try stderr.flush();
        return error.RunFailed;
    };
    defer child.kill(io);

    return child.wait(io) catch |err| {
        try stderr.print("error: command wait failed for {s}: {s}\n", .{ label, @errorName(err) });
        try stderr.flush();
        return error.RunFailed;
    };
}

fn termIsSuccess(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn termIsInterrupted(term: std.process.Child.Term) bool {
    return switch (term) {
        .signal => |sig| sig == .INT,
        else => false,
    };
}

test "parseRunOptions parses shared and platform flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseRunOptions(&.{
        "android",
        "examples/android/ZiggyExample",
        "--device",
        "emulator-5554",
        "--module",
        "app",
        "--debugger",
        "none",
        "--once",
    }, &err_writer.writer);

    try std.testing.expectEqual(Platform.android, options.platform);
    try std.testing.expectEqualStrings("examples/android/ZiggyExample", options.project_dir);
    try std.testing.expectEqualStrings("emulator-5554", options.device_selector.?);
    try std.testing.expectEqual(DebuggerMode.none, options.debugger);
    try std.testing.expect(options.once);
}

test "parseRunOptions rejects mixed platform flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    try std.testing.expectError(
        error.RunFailed,
        parseRunOptions(&.{
            "ios",
            "examples/ios/ZiggyExample",
            "--module",
            "custom-module",
        }, &err_writer.writer),
    );
}

test "parseAndroidDevicesOutput picks connected devices" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var devices = try parseAndroidDevicesOutput(
        arena,
        "List of devices attached\n" ++
            "emulator-5554 device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1\n" ++
            "ZX1G22 unauthorized usb:1-2 transport_id:2\n",
    );

    try std.testing.expectEqual(@as(usize, 1), devices.items.len);
    try std.testing.expectEqualStrings("emulator-5554", devices.items[0].serial);
    try std.testing.expectEqualStrings("sdk_gphone64_arm64", devices.items[0].model);
}

test "parseAaptBadging extracts app id and launch activity" {
    var app_id: ?[]const u8 = null;
    var activity: ?[]const u8 = null;
    parseAaptBadging(
        "package: name='dev.ziggy.demo' versionCode='1' versionName='1.0'\n" ++
            "launchable-activity: name='dev.ziggy.demo.MainActivity' label='' icon=''\n",
        &app_id,
        &activity,
    );
    try std.testing.expectEqualStrings("dev.ziggy.demo", app_id.?);
    try std.testing.expectEqualStrings("dev.ziggy.demo.MainActivity", activity.?);
}

test "extractBuildSetting parses xcodebuild output line" {
    const setting = extractBuildSetting(
        "Build settings for action build and target Demo:\n" ++
            "    TARGET_BUILD_DIR = /tmp/demo\n" ++
            "    PRODUCT_BUNDLE_IDENTIFIER = dev.ziggy.demo\n",
        "PRODUCT_BUNDLE_IDENTIFIER",
    );
    try std.testing.expect(setting != null);
    try std.testing.expectEqualStrings("dev.ziggy.demo", setting.?);
}

test "extractXmlAttribute parses manifest package and activity" {
    const manifest =
        "<manifest package=\"dev.ziggy.sample\">\n" ++
        "  <application>\n" ++
        "    <activity android:name=\".MainActivity\" android:exported=\"true\" />\n" ++
        "  </application>\n" ++
        "</manifest>\n";
    try std.testing.expectEqualStrings("dev.ziggy.sample", extractXmlAttribute(manifest, "manifest", "package").?);
    try std.testing.expectEqualStrings(".MainActivity", extractXmlAttribute(manifest, "activity", "android:name").?);
}

test "chooseAndroidTarget selects avd by selector" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    const target = try chooseAndroidTarget(
        std.testing.allocator,
        std.testing.io,
        &err_writer.writer,
        &out_writer.writer,
        &.{},
        &.{"Pixel_9_API_35"},
        "avd:Pixel_9_API_35",
        true,
    );
    switch (target) {
        .avd => |name| try std.testing.expectEqualStrings("Pixel_9_API_35", name),
        else => return error.TestExpectedEqual,
    }
}

test "isTransientIosLaunchFailure detects flaky launch output" {
    try std.testing.expect(isTransientIosLaunchFailure(
        "",
        "An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=3):\nApplication launch for 'dev.ziggy.example' did not return a process handle nor launch error. No such process\n",
    ));
    try std.testing.expect(!isTransientIosLaunchFailure("", "Missing bundle identifier"));
}

test "chooseIosDevice resolves selector by name and udid" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    const devices = [_]IosDevice{
        .{
            .name = "iPhone 17 Pro",
            .udid = "UDID-1",
            .runtime = "iOS.26.2",
            .state = "Booted",
        },
        .{
            .name = "iPhone 17",
            .udid = "UDID-2",
            .runtime = "iOS.26.2",
            .state = "Shutdown",
        },
    };

    const by_name = try chooseIosDevice(
        std.testing.allocator,
        std.testing.io,
        &err_writer.writer,
        &out_writer.writer,
        &devices,
        "iphone 17 pro",
        true,
    );
    try std.testing.expectEqualStrings("UDID-1", by_name.udid);

    const by_udid = try chooseIosDevice(
        std.testing.allocator,
        std.testing.io,
        &err_writer.writer,
        &out_writer.writer,
        &devices,
        "UDID-2",
        true,
    );
    try std.testing.expectEqualStrings("iPhone 17", by_udid.name);
}

test "filterIosDevicesBySupportedIds keeps only supported devices" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const devices = [_]IosDevice{
        .{ .name = "A", .udid = "ID-A", .runtime = "iOS.26.1", .state = "Booted" },
        .{ .name = "B", .udid = "ID-B", .runtime = "iOS.26.1", .state = "Shutdown" },
    };
    const supported = [_][]const u8{"ID-B"};

    const filtered = try filterIosDevicesBySupportedIds(arena, &devices, &supported);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("ID-B", filtered[0].udid);
}

test "extractInlineField parses destination id from xcodebuild output" {
    const line =
        "{ platform:iOS Simulator, id:CAF0B1F5-83DF-477B-8955-43802FC77D58, OS:26.1, name:17 Pro 26.1 }";
    const id = extractInlineField(line, "id:");
    try std.testing.expect(id != null);
    try std.testing.expectEqualStrings("CAF0B1F5-83DF-477B-8955-43802FC77D58", id.?);
}

test "parseLaunchPid extracts simulator pid" {
    const pid = parseLaunchPid("dev.ziggy.example.ios: 75668");
    try std.testing.expect(pid != null);
    try std.testing.expectEqual(@as(u32, 75668), pid.?);
}

test "resolveAndroidDebugger auto defaults to logcat" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const mode = try resolveAndroidDebugger(std.testing.allocator, std.testing.io, &err_writer.writer, .auto);
    try std.testing.expectEqual(DebuggerMode.logcat, mode);
}

test "resolveIosFfiLibraryPath prefers env path when it exists" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    try tmp.dir.writeFile(io, .{
        .sub_path = "libziggyffi.dylib",
        .data = "",
    });

    const tmp_root = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    const ffi_path = try std.fmt.allocPrint(arena, "{s}{s}libziggyffi.dylib", .{ tmp_root, std.fs.path.sep_str });

    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();
    try env.put("ZIGGY_FFI_LIB", ffi_path);

    const cwd = try std.process.currentPathAlloc(io, arena);
    const expected = try std.fs.path.resolve(arena, &.{ cwd, ffi_path });
    const resolved = try resolveIosFfiLibraryPath(arena, io, &env);
    try std.testing.expect(resolved != null);
    try std.testing.expectEqualStrings(expected, resolved.?);
}
