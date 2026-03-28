//! Android run helper functions for preselected devices and log streaming.
const std = @import("std");
const Io = std.Io;

const android_debug = @import("android_debug.zig");
const process = @import("process_supervisor.zig");
const types = @import("types.zig");

/// Resolves a preselected Android device when unified run already chose target.
pub fn resolvePreselectedAndroidDevice(
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

/// Streams Android logs with liveness + timeout watchdog semantics.
pub fn streamAndroidLogs(
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

        const startup_dump = process.runCapture(arena, io, .{
            .argv = &.{ "adb", "-s", serial, "logcat", "--pid", pid_text, "-d" },
            .label = "dump Android startup logs",
        }, .{
            .stdout_bytes = 4 * 1024 * 1024,
            .stderr_bytes = 512 * 1024,
        }) catch null;
        if (startup_dump) |dump| {
            if (dump.stdout.len > 0) {
                try stdout.writeAll(dump.stdout);
                if (dump.stdout[dump.stdout.len - 1] != '\n') try stdout.writeAll("\n");
            }
            if (dump.stderr.len > 0) {
                try stderr.writeAll(dump.stderr);
                if (dump.stderr[dump.stderr.len - 1] != '\n') try stderr.writeAll("\n");
                try stderr.flush();
            }
        }

        try stdout.print("streaming logcat for pid {s} (Ctrl+C to stop)...\n", .{pid_text});
        try stdout.flush();
        const monitor_result = try process.runInheritMonitored(
            arena,
            io,
            stderr,
            stdout,
            .{
                .argv = &.{ "adb", "-s", serial, "logcat", "--pid", pid_text, "-T", "1" },
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
