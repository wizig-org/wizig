//! Unified run mode that auto-detects iOS/Android hosts and devices.
const std = @import("std");
const Io = std.Io;

const legacy = @import("legacy.zig");
const codegen_cmd = @import("../commands/codegen/root.zig");

const Allocator = std.mem.Allocator;

const Platform = enum {
    ios,
    android,
};

const UnifiedOptions = struct {
    project_root: []const u8 = ".",
    device_selector: ?[]const u8 = null,
    debugger_mode: ?[]const u8 = null,
    non_interactive: bool = false,
    once: bool = false,
    regenerate_host: bool = false,
};

const Candidate = struct {
    platform: Platform,
    id: []const u8,
    name: []const u8,
    state: []const u8,
    project_dir: []const u8,
};

const DeviceInfo = struct {
    id: []const u8,
    name: []const u8,
    state: []const u8,
};

/// Discovers available targets and runs the selected host flow.
pub fn run(
    arena: Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed = parseUnifiedOptions(args, stderr) catch {
        try printUsage(stderr);
        try stderr.flush();
        return error.RunFailed;
    };

    const project_root = try resolveProjectRoot(arena, io, parsed.project_root);
    var log_lines = std.ArrayList(u8).empty;
    defer log_lines.deinit(arena);

    const log_path = try buildLogPath(arena, io, project_root);
    defer {
        writeFileAtomically(io, log_path, log_lines.items) catch {};
    }

    try appendLogLine(arena, &log_lines, "wizig run unified\n", .{});
    try appendLogLine(arena, &log_lines, "project_root={s}\n", .{project_root});
    if (parsed.debugger_mode) |mode| {
        try appendLogLine(arena, &log_lines, "debugger={s}\n", .{mode});
    } else {
        try appendLogLine(arena, &log_lines, "debugger=auto\n", .{});
    }
    try appendLogLine(
        arena,
        &log_lines,
        "regenerate_host={s}\n",
        .{if (parsed.regenerate_host) "true" else "false"},
    );

    const ios_dir = try joinPath(arena, project_root, "ios");
    const android_dir = try joinPath(arena, project_root, "android");

    const has_ios = hasIosHost(arena, io, ios_dir);
    const has_android = hasAndroidHost(io, android_dir);
    try appendLogLine(arena, &log_lines, "has_ios_host={s}\n", .{if (has_ios) "true" else "false"});
    try appendLogLine(arena, &log_lines, "has_android_host={s}\n", .{if (has_android) "true" else "false"});
    if (!has_ios and !has_android) {
        try stderr.print(
            "error: no generated app hosts found under '{s}' (expected ios/ and/or android/)\n",
            .{project_root},
        );
        try appendLogLine(arena, &log_lines, "status=failed\n", .{});
        try appendLogLine(arena, &log_lines, "error=no_generated_hosts\n", .{});
        try stdout.print("run log: {s}\n", .{log_path});
        try stdout.flush();
        return error.RunFailed;
    }

    try runCodegenPreflight(arena, io, stderr, stdout, project_root, &log_lines);

    var candidates = std.ArrayList(Candidate).empty;
    defer candidates.deinit(arena);
    var ios_discovery_failed = false;
    var android_discovery_failed = false;

    if (has_ios) {
        const ios_devices = discoverIosDevicesNonShutdown(arena, io, stderr) catch |err| blk: {
            ios_discovery_failed = true;
            try stderr.print("warning: iOS device discovery failed: {s}\n", .{@errorName(err)});
            try stderr.flush();
            try appendLogLine(arena, &log_lines, "ios_discovery=failed:{s}\n", .{@errorName(err)});
            break :blk &[_]DeviceInfo{};
        };
        for (ios_devices) |device| {
            try candidates.append(arena, .{
                .platform = .ios,
                .id = device.id,
                .name = device.name,
                .state = device.state,
                .project_dir = ios_dir,
            });
        }
        if (!ios_discovery_failed) {
            try appendLogLine(arena, &log_lines, "ios_devices={d}\n", .{ios_devices.len});
        }
    }

    if (has_android) {
        const android_devices = discoverAndroidDevices(arena, io, stderr) catch |err| blk: {
            android_discovery_failed = true;
            try stderr.print("warning: Android device discovery failed: {s}\n", .{@errorName(err)});
            try stderr.flush();
            try appendLogLine(arena, &log_lines, "android_discovery=failed:{s}\n", .{@errorName(err)});
            break :blk &[_]DeviceInfo{};
        };
        for (android_devices) |device| {
            try candidates.append(arena, .{
                .platform = .android,
                .id = device.id,
                .name = device.name,
                .state = device.state,
                .project_dir = android_dir,
            });
        }
        if (!android_discovery_failed) {
            try appendLogLine(arena, &log_lines, "android_devices={d}\n", .{android_devices.len});
        }
    }

    if (candidates.items.len == 0) {
        if (ios_discovery_failed or android_discovery_failed) {
            try stderr.writeAll("error: no runnable targets found after platform discovery failures\n");
        } else {
            try stderr.writeAll("error: no available iOS (non-shutdown) or Android devices found\n");
        }
        try appendLogLine(arena, &log_lines, "status=failed\n", .{});
        try appendLogLine(arena, &log_lines, "error=no_candidates\n", .{});
        try stdout.print("run log: {s}\n", .{log_path});
        try stdout.flush();
        return error.RunFailed;
    }

    const selected = try chooseCandidate(
        arena,
        io,
        stderr,
        stdout,
        candidates.items,
        parsed.device_selector,
        parsed.non_interactive,
    );
    try appendLogLine(arena, &log_lines, "selected_platform={s}\n", .{platformLabel(selected.platform)});
    try appendLogLine(arena, &log_lines, "selected_device={s}\n", .{selected.id});
    try appendLogLine(arena, &log_lines, "selected_name={s}\n", .{selected.name});

    try stdout.print(
        "selected target: [{s}] {s} [{s}] ({s})\n",
        .{ platformLabel(selected.platform), selected.name, selected.id, selected.state },
    );
    try stdout.flush();

    var delegated_args = std.ArrayList([]const u8).empty;
    defer delegated_args.deinit(arena);

    try delegated_args.append(arena, platformLabel(selected.platform));
    try delegated_args.append(arena, selected.project_dir);
    try delegated_args.append(arena, "--device");
    try delegated_args.append(arena, selected.id);
    try delegated_args.append(arena, "--non-interactive");
    // Internal legacy hint: unified run already selected a concrete target.
    try delegated_args.append(arena, "--__wizig-skip-device-discovery");
    // Unified already ran codegen preflight.
    try delegated_args.append(arena, "--__wizig-skip-codegen");
    if (parsed.once) {
        try delegated_args.append(arena, "--once");
    }
    if (parsed.regenerate_host) {
        try delegated_args.append(arena, "--regenerate-host");
    }
    if (parsed.debugger_mode) |mode| {
        try delegated_args.append(arena, "--debugger");
        try delegated_args.append(arena, mode);
    } else {
        try delegated_args.append(arena, "--debugger");
        try delegated_args.append(arena, "auto");
    }

    legacy.run(arena, io, parent_environ_map, stderr, stdout, delegated_args.items) catch |err| {
        try appendLogLine(arena, &log_lines, "status=failed\n", .{});
        try appendLogLine(arena, &log_lines, "error={s}\n", .{@errorName(err)});
        try stdout.print("run log: {s}\n", .{log_path});
        try stdout.flush();
        return err;
    };

    try appendLogLine(arena, &log_lines, "status=ok\n", .{});
    try stdout.print("run log: {s}\n", .{log_path});
    try stdout.flush();
}

/// Writes unified run usage help.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Unified run options:\n" ++
            "  wizig run [project_dir] [--device <id_or_name>] [--debugger <mode>] [--non-interactive] [--once] [--regenerate-host]\n" ++
            "\n",
    );
}

fn parseUnifiedOptions(args: []const []const u8, stderr: *Io.Writer) !UnifiedOptions {
    var options = UnifiedOptions{};

    var i: usize = 0;
    if (i < args.len and !std.mem.startsWith(u8, args[i], "--")) {
        options.project_root = args[i];
        i += 1;
    }

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
        if (std.mem.eql(u8, arg, "--regenerate-host")) {
            options.regenerate_host = true;
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
            options.debugger_mode = value;
        } else {
            try stderr.print("error: unknown run option '{s}'\n", .{arg});
            return error.RunFailed;
        }
        i += 2;
    }

    return options;
}

fn resolveProjectRoot(arena: Allocator, io: std.Io, root: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(root)) {
        return arena.dupe(u8, root);
    }
    const cwd = try std.process.currentPathAlloc(io, arena);
    return std.fs.path.resolve(arena, &.{ cwd, root });
}

fn hasIosHost(arena: Allocator, io: std.Io, ios_dir: []const u8) bool {
    if (!pathExists(io, ios_dir)) return false;

    const result = runCapture(
        arena,
        io,
        null,
        &.{ "find", ios_dir, "-maxdepth", "1", "-type", "d", "-name", "*.xcodeproj" },
        null,
    ) catch return false;
    if (!termIsSuccess(result.term)) return false;

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len > 0) return true;
    }
    return false;
}

fn hasAndroidHost(io: std.Io, android_dir: []const u8) bool {
    if (!pathExists(io, android_dir)) return false;

    const app_build_kts = std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}app{s}build.gradle.kts", .{
        android_dir,
        std.fs.path.sep_str,
        std.fs.path.sep_str,
    }) catch return false;
    defer std.heap.page_allocator.free(app_build_kts);
    if (pathExists(io, app_build_kts)) return true;

    const app_build = std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}app{s}build.gradle", .{
        android_dir,
        std.fs.path.sep_str,
        std.fs.path.sep_str,
    }) catch return false;
    defer std.heap.page_allocator.free(app_build);
    return pathExists(io, app_build);
}

fn discoverIosDevicesNonShutdown(arena: Allocator, io: std.Io, stderr: *Io.Writer) ![]DeviceInfo {
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

    var devices = std.ArrayList(DeviceInfo).empty;

    var runtime_it = devices_value.object.iterator();
    while (runtime_it.next()) |runtime_entry| {
        const runtime_key = runtime_entry.key_ptr.*;
        if (std.mem.indexOf(u8, runtime_key, "iOS-") == null) continue;

        const runtime_value = runtime_entry.value_ptr.*;
        if (runtime_value != .array) continue;

        for (runtime_value.array.items) |device_value| {
            if (device_value != .object) continue;

            const name = jsonObjectString(device_value.object, "name") orelse continue;
            const udid = jsonObjectString(device_value.object, "udid") orelse continue;
            const state = jsonObjectString(device_value.object, "state") orelse "Unknown";
            const available = jsonObjectBool(device_value.object, "isAvailable") orelse true;
            if (!available) continue;
            if (std.mem.eql(u8, state, "Shutdown")) continue;

            try devices.append(arena, .{
                .id = try arena.dupe(u8, udid),
                .name = try arena.dupe(u8, name),
                .state = try arena.dupe(u8, state),
            });
        }
    }

    std.mem.sort(DeviceInfo, devices.items, {}, lessDeviceInfo);
    return devices.toOwnedSlice(arena);
}

fn discoverAndroidDevices(arena: Allocator, io: std.Io, stderr: *Io.Writer) ![]DeviceInfo {
    const result = try runCaptureChecked(
        arena,
        io,
        null,
        &.{ "adb", "devices", "-l" },
        null,
        stderr,
        "discover Android devices",
    );

    var devices = std.ArrayList(DeviceInfo).empty;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
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

        const name = model_name orelse serial;
        try devices.append(arena, .{
            .id = try arena.dupe(u8, serial),
            .name = try arena.dupe(u8, name),
            .state = try arena.dupe(u8, state),
        });
    }

    std.mem.sort(DeviceInfo, devices.items, {}, lessDeviceInfo);
    return devices.toOwnedSlice(arena);
}

fn chooseCandidate(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    candidates: []const Candidate,
    selector: ?[]const u8,
    non_interactive: bool,
) !Candidate {
    if (selector) |needle| {
        if (findCandidateBySelector(candidates, needle)) |found| return found;
        try stderr.print("error: target '{s}' not found in available devices\n", .{needle});
        return error.RunFailed;
    }

    if (candidates.len == 1) return candidates[0];
    if (non_interactive) {
        try stderr.writeAll("error: multiple targets found; pass --device\n");
        return error.RunFailed;
    }

    try stdout.writeAll("available run targets:\n");
    for (candidates, 0..) |candidate, idx| {
        try stdout.print(
            "  {d}. [{s}] {s} [{s}] ({s})\n",
            .{ idx + 1, platformLabel(candidate.platform), candidate.name, candidate.id, candidate.state },
        );
    }
    try stdout.flush();

    const index = try promptSelection(arena, io, stderr, stdout, candidates.len);
    return candidates[index];
}

fn findCandidateBySelector(candidates: []const Candidate, selector: []const u8) ?Candidate {
    var platform_filter: ?Platform = null;
    var raw_selector = selector;
    if (std.mem.indexOfScalar(u8, selector, ':')) |separator| {
        const prefix = selector[0..separator];
        const suffix = selector[separator + 1 ..];
        if (std.ascii.eqlIgnoreCase(prefix, "ios")) {
            platform_filter = .ios;
            raw_selector = suffix;
        } else if (std.ascii.eqlIgnoreCase(prefix, "android")) {
            platform_filter = .android;
            raw_selector = suffix;
        }
    }

    for (candidates) |candidate| {
        if (platform_filter) |filtered_platform| {
            if (candidate.platform != filtered_platform) continue;
        }
        if (std.mem.eql(u8, candidate.id, raw_selector)) return candidate;
        if (std.ascii.eqlIgnoreCase(candidate.name, raw_selector)) return candidate;
    }
    return null;
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

fn buildLogPath(arena: Allocator, io: std.Io, project_root: []const u8) ![]const u8 {
    const logs_dir = try std.fmt.allocPrint(
        arena,
        "{s}{s}.wizig{s}logs",
        .{ project_root, std.fs.path.sep_str, std.fs.path.sep_str },
    );
    std.Io.Dir.cwd().createDirPath(io, logs_dir) catch {};

    return std.fmt.allocPrint(arena, "{s}{s}run.log", .{ logs_dir, std.fs.path.sep_str });
}

fn appendLogLine(arena: Allocator, log_lines: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const line = try std.fmt.allocPrint(arena, fmt, args);
    try log_lines.appendSlice(arena, line);
}

fn runCodegenPreflight(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    log_lines: *std.ArrayList(u8),
) !void {
    const contract = try codegen_cmd.resolveApiContract(arena, io, stderr, project_root, null);
    const outcome = codegen_cmd.ensureProjectGenerated(
        arena,
        io,
        stderr,
        stdout,
        project_root,
        if (contract) |resolved| resolved.path else null,
        .{},
    ) catch |err| {
        try appendLogLine(arena, log_lines, "codegen=failed:{s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.RunFailed;
    };

    switch (outcome) {
        .skipped => try appendLogLine(arena, log_lines, "codegen=skipped:fingerprint\n", .{}),
        .generated => try appendLogLine(arena, log_lines, "codegen=ok\n", .{}),
    }
}

fn writeFileAtomically(io: std.Io, path: []const u8, contents: []const u8) !void {
    var atomic_file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .make_path = true,
        .replace = true,
    });
    defer atomic_file.deinit(io);

    try atomic_file.file.writeStreamingAll(io, contents);
    try atomic_file.replace(io);
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

fn platformLabel(platform: Platform) []const u8 {
    return switch (platform) {
        .ios => "ios",
        .android => "android",
    };
}

fn lessDeviceInfo(_: void, a: DeviceInfo, b: DeviceInfo) bool {
    return std.ascii.lessThanIgnoreCase(a.name, b.name);
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

fn childCwd(path: ?[]const u8) std.process.Child.Cwd {
    if (path) |cwd_path| return .{ .path = cwd_path };
    return .inherit;
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
    context: []const u8,
) !std.process.RunResult {
    const result = runCapture(arena, io, cwd_path, argv, environ_map) catch |err| {
        try stderr.print("error: failed to spawn command for {s}: {s}\n", .{ context, @errorName(err) });
        try stderr.flush();
        return error.RunFailed;
    };

    if (!termIsSuccess(result.term)) {
        try stderr.print("error: command failed for {s}: {s}\n", .{ context, argv[0] });
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

fn termIsSuccess(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

test "parseUnifiedOptions defaults" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseUnifiedOptions(&.{}, &err_writer.writer);
    try std.testing.expectEqualStrings(".", options.project_root);
    try std.testing.expect(options.device_selector == null);
    try std.testing.expect(options.debugger_mode == null);
    try std.testing.expect(!options.non_interactive);
    try std.testing.expect(!options.once);
    try std.testing.expect(!options.regenerate_host);
}

test "parseUnifiedOptions parses project and flags" {
    var err_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_writer.deinit();

    const options = try parseUnifiedOptions(
        &.{ "examples/app/WizigExample", "--device", "emulator-5554", "--debugger", "none", "--once", "--regenerate-host" },
        &err_writer.writer,
    );
    try std.testing.expectEqualStrings("examples/app/WizigExample", options.project_root);
    try std.testing.expectEqualStrings("emulator-5554", options.device_selector.?);
    try std.testing.expectEqualStrings("none", options.debugger_mode.?);
    try std.testing.expect(options.once);
    try std.testing.expect(options.regenerate_host);
}
