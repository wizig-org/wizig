//! iOS project/build and app launch helpers.
//!
//! This module encapsulates Xcode project lookup/regeneration and resilient
//! simulator launch routines used by the iOS run flow.
const std = @import("std");
const Io = std.Io;

const fs_utils = @import("fs_utils.zig");
const process = @import("process_supervisor.zig");
const text_utils = @import("text_utils.zig");
const tooling = @import("tooling.zig");

/// Finds the `.xcodeproj` directory inside the host iOS project directory.
pub fn findXcodeProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
) ![]const u8 {
    const result = try process.runCaptureChecked(arena, io, stderr, .{
        .argv = &.{ "find", project_dir, "-maxdepth", "1", "-type", "d", "-name", "*.xcodeproj" },
        .label = "locate Xcode project",
    }, .{});

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

/// Regenerates iOS host project with xcodegen when requested and available.
pub fn maybeRegenerateIosProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_dir: []const u8,
) !void {
    const project_spec = try fs_utils.joinPath(arena, project_dir, "project.yml");
    if (!fs_utils.pathExists(io, project_spec)) return;

    if (!tooling.commandExists(arena, io, "xcodegen")) {
        try stderr.writeAll("warning: xcodegen not found; skipping iOS project regeneration\n");
        try stderr.flush();
        return;
    }

    try stdout.writeAll("regenerating iOS project...\n");
    try stdout.flush();
    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "xcodegen", "generate" },
        .cwd_path = project_dir,
        .label = "generate iOS project",
    });
}

/// Launches iOS app and retries transient simulator launch failures.
pub fn launchIosAppWithRetry(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    udid: []const u8,
    bundle_id: []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !std.process.RunResult {
    var attempt: usize = 0;
    while (attempt < 5) : (attempt += 1) {
        const result = process.runCapture(arena, io, .{
            .argv = &.{ "xcrun", "simctl", "launch", udid, bundle_id },
            .environ_map = environ_map,
            .label = "launch iOS app",
        }, .{}) catch |err| {
            try stderr.print("error: failed to spawn command for launch iOS app: {s}\n", .{@errorName(err)});
            try stderr.flush();
            return error.RunFailed;
        };

        const pid = text_utils.parseLaunchPid(result.stdout);
        if (process.termIsSuccess(result.term) and pid != null) {
            return result;
        }

        const can_retry = if (process.termIsSuccess(result.term)) pid == null else isTransientIosLaunchFailure(result.stdout, result.stderr);
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
        _ = process.runCapture(arena, io, .{ .argv = &.{ "xcrun", "simctl", "terminate", udid, bundle_id }, .label = "terminate iOS app after transient failure" }, .{}) catch {};
        _ = process.runCapture(arena, io, .{ .argv = &.{ "xcrun", "simctl", "bootstatus", udid, "-b" }, .label = "wait iOS bootstatus after transient failure" }, .{}) catch {};
        std.Io.sleep(io, .fromMilliseconds(700), .awake) catch {};
    }

    return error.RunFailed;
}

/// Launches iOS app with attached simulator console pty and transient retries.
pub fn launchIosAppWithConsoleRetry(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    udid: []const u8,
    bundle_id: []const u8,
    environ_map: ?*const std.process.Environ.Map,
    monitor_timeout_seconds: ?u64,
) !void {
    const liveness_probe = process.LivenessProbe{
        .spec = .{
            .argv = &.{ "xcrun", "simctl", "spawn", udid, "launchctl", "list" },
            .label = "check iOS app liveness",
        },
        .required_substring = bundle_id,
    };
    const watchdog: process.MonitorWatchdog = .{
        .timeout_seconds = monitor_timeout_seconds,
        .liveness_probe = liveness_probe,
    };

    var attempt: usize = 0;
    while (attempt < 5) : (attempt += 1) {
        const monitor_result = try process.runInheritMonitored(
            arena,
            io,
            stderr,
            stdout,
            .{
                .argv = &.{ "xcrun", "simctl", "launch", "--terminate-running-process", "--console-pty", udid, bundle_id },
                .environ_map = environ_map,
                .label = "launch iOS app with console",
            },
            watchdog,
        );
        switch (monitor_result.stop_reason) {
            .interrupted => return,
            .timeout => return,
            .app_liveness_lost => return,
            .exited => {
                if (process.termIsSuccess(monitor_result.term)) return;
            },
        }

        if (attempt + 1 >= 5) {
            try stderr.writeAll("error: command failed for launch iOS app with console\n");
            try stderr.flush();
            return error.RunFailed;
        }

        try stderr.print("warning: transient iOS console launch failure (attempt {d}/5), retrying...\n", .{attempt + 1});
        try stderr.flush();
        _ = process.runCapture(arena, io, .{ .argv = &.{ "xcrun", "simctl", "terminate", udid, bundle_id }, .label = "terminate iOS app after console transient failure" }, .{}) catch {};
        _ = process.runCapture(arena, io, .{ .argv = &.{ "xcrun", "simctl", "bootstatus", udid, "-b" }, .label = "wait iOS bootstatus after console transient failure" }, .{}) catch {};
        std.Io.sleep(io, .fromMilliseconds(700), .awake) catch {};
    }

    return error.RunFailed;
}

fn isTransientIosLaunchFailure(stdout: []const u8, stderr: []const u8) bool {
    return text_utils.containsAny(stdout, &.{
        "did not return a process handle nor launch error",
        "No such process",
        "Operation timed out",
    }) or text_utils.containsAny(stderr, &.{
        "did not return a process handle nor launch error",
        "No such process",
        "Operation timed out",
    });
}
