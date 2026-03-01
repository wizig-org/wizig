//! Unified run orchestration entrypoint.
//!
//! Unified mode discovers available iOS/Android targets, selects one, logs
//! run metadata, then delegates concrete execution to platform runners.
const std = @import("std");
const Io = std.Io;

const fs_utils = @import("../platform/fs_utils.zig");
const discovery = @import("discovery.zig");
const logging_codegen = @import("logging_codegen.zig");
const options_mod = @import("options.zig");
const platform_run = @import("../platform/root.zig");
const types = @import("types.zig");

/// Discovers available targets and runs the selected host flow.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const parsed = options_mod.parseUnifiedOptions(args, stderr) catch {
        try printUsage(stderr);
        try stderr.flush();
        return error.RunFailed;
    };

    const project_root = try options_mod.resolveProjectRoot(arena, io, parsed.project_root);
    var log_lines = std.ArrayList(u8).empty;
    defer log_lines.deinit(arena);

    const log_path = try logging_codegen.buildLogPath(arena, io, project_root);
    defer fs_utils.writeFileAtomically(io, log_path, log_lines.items) catch {};

    try logging_codegen.appendLogLine(arena, &log_lines, "wizig run unified\n", .{});
    try logging_codegen.appendLogLine(arena, &log_lines, "project_root={s}\n", .{project_root});
    try logging_codegen.appendLogLine(arena, &log_lines, "debugger={s}\n", .{parsed.debugger_mode orelse "auto"});

    const ios_dir = try fs_utils.joinPath(arena, project_root, "ios");
    const android_dir = try fs_utils.joinPath(arena, project_root, "android");

    const has_ios = discovery.hasIosHost(arena, io, ios_dir);
    const has_android = discovery.hasAndroidHost(io, android_dir);
    try logging_codegen.appendLogLine(arena, &log_lines, "has_ios_host={s}\n", .{if (has_ios) "true" else "false"});
    try logging_codegen.appendLogLine(arena, &log_lines, "has_android_host={s}\n", .{if (has_android) "true" else "false"});
    if (!has_ios and !has_android) {
        try stderr.print("error: no generated app hosts found under '{s}' (expected ios/ and/or android/)\n", .{project_root});
        try logging_codegen.appendLogLine(arena, &log_lines, "status=failed\n", .{});
        try stdout.print("run log: {s}\n", .{log_path});
        try stdout.flush();
        return error.RunFailed;
    }

    try logging_codegen.runCodegenPreflight(arena, io, stderr, stdout, project_root, &log_lines);

    var candidates = std.ArrayList(types.Candidate).empty;
    defer candidates.deinit(arena);
    var ios_discovery_failed = false;
    var android_discovery_failed = false;

    if (has_ios) {
        const ios_devices = discovery.discoverIosDevicesNonShutdown(arena, io, stderr) catch |err| blk: {
            ios_discovery_failed = true;
            try stderr.print("warning: iOS device discovery failed: {s}\n", .{@errorName(err)});
            try stderr.flush();
            try logging_codegen.appendLogLine(arena, &log_lines, "ios_discovery=failed:{s}\n", .{@errorName(err)});
            break :blk &[_]types.DeviceInfo{};
        };
        for (ios_devices) |device| {
            try candidates.append(arena, .{ .platform = .ios, .id = device.id, .name = device.name, .state = device.state, .project_dir = ios_dir });
        }
        if (!ios_discovery_failed) {
            try logging_codegen.appendLogLine(arena, &log_lines, "ios_devices={d}\n", .{ios_devices.len});
        }
    }

    if (has_android) {
        const android_devices = discovery.discoverAndroidDevices(arena, io, stderr) catch |err| blk: {
            android_discovery_failed = true;
            try stderr.print("warning: Android device discovery failed: {s}\n", .{@errorName(err)});
            try stderr.flush();
            try logging_codegen.appendLogLine(arena, &log_lines, "android_discovery=failed:{s}\n", .{@errorName(err)});
            break :blk &[_]types.DeviceInfo{};
        };
        for (android_devices) |device| {
            try candidates.append(arena, .{ .platform = .android, .id = device.id, .name = device.name, .state = device.state, .project_dir = android_dir });
        }
        if (!android_discovery_failed) {
            try logging_codegen.appendLogLine(arena, &log_lines, "android_devices={d}\n", .{android_devices.len});
        }
    }

    if (candidates.items.len == 0) {
        if (ios_discovery_failed or android_discovery_failed) {
            try stderr.writeAll("error: no runnable targets found after platform discovery failures\n");
        } else {
            try stderr.writeAll("error: no available iOS (non-shutdown) or Android devices found\n");
        }
        try logging_codegen.appendLogLine(arena, &log_lines, "status=failed\n", .{});
        try stdout.print("run log: {s}\n", .{log_path});
        try stdout.flush();
        return error.RunFailed;
    }

    const selected = try discovery.chooseCandidate(arena, io, stderr, stdout, candidates.items, parsed.device_selector, parsed.non_interactive);
    try logging_codegen.appendLogLine(arena, &log_lines, "selected_platform={s}\n", .{types.platformLabel(selected.platform)});
    try logging_codegen.appendLogLine(arena, &log_lines, "selected_device={s}\n", .{selected.id});
    try logging_codegen.appendLogLine(arena, &log_lines, "selected_name={s}\n", .{selected.name});
    try stdout.print("selected target: [{s}] {s} [{s}] ({s})\n", .{ types.platformLabel(selected.platform), selected.name, selected.id, selected.state });
    try stdout.flush();

    var delegated_args = std.ArrayList([]const u8).empty;
    defer delegated_args.deinit(arena);

    try delegated_args.append(arena, types.platformLabel(selected.platform));
    try delegated_args.append(arena, selected.project_dir);
    try delegated_args.appendSlice(arena, &.{ "--device", selected.id, "--non-interactive", "--__wizig-skip-device-discovery", "--__wizig-skip-codegen" });
    if (parsed.once) try delegated_args.append(arena, "--once");
    if (parsed.regenerate_host) try delegated_args.append(arena, "--regenerate-host");
    try delegated_args.appendSlice(arena, &.{ "--debugger", parsed.debugger_mode orelse "auto" });

    platform_run.run(arena, io, parent_environ_map, stderr, stdout, delegated_args.items) catch |err| {
        try logging_codegen.appendLogLine(arena, &log_lines, "status=failed\n", .{});
        try logging_codegen.appendLogLine(arena, &log_lines, "error={s}\n", .{@errorName(err)});
        try stdout.print("run log: {s}\n", .{log_path});
        try stdout.flush();
        return err;
    };
    try logging_codegen.appendLogLine(arena, &log_lines, "status=ok\n", .{});
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
