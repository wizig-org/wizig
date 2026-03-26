//! Android install, launch, debugger, and log-monitor attachment.
//!
//! This module owns the final run step after the APK has been built and the
//! launch metadata has been resolved.
const std = @import("std");
const Io = std.Io;

const android_debug = @import("../android_debug.zig");
const android_log_stream = @import("../android_log_stream.zig");
const config_parse = @import("../config_parse.zig");
const process = @import("../process_supervisor.zig");
const types = @import("../types.zig");

const metadata = @import("metadata.zig");

/// Installs the APK, launches the app, and attaches the requested monitor.
pub fn launchAndroidApp(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    serial: []const u8,
    apk: []const u8,
    launch_metadata: metadata.AndroidLaunchMetadata,
    debugger_mode: types.DebuggerMode,
    once: bool,
    monitor_timeout_seconds: ?u64,
) !void {
    const component = try config_parse.normalizeAndroidComponent(arena, launch_metadata.app_id, launch_metadata.activity);

    try process.runInheritChecked(io, stderr, .{
        .argv = &.{ "adb", "-s", serial, "install", "-r", "-t", apk },
        .label = "install Android app",
    });
    _ = process.runCapture(arena, io, .{
        .argv = &.{ "adb", "-s", serial, "shell", "am", "force-stop", launch_metadata.app_id },
        .label = "force-stop Android app",
    }, .{}) catch {};

    if (debugger_mode == .jdb) {
        try process.runInheritChecked(io, stderr, .{
            .argv = &.{ "adb", "-s", serial, "shell", "am", "start", "-D", "-n", component },
            .label = "launch Android app in debug-wait mode",
        });
    } else {
        try process.runInheritChecked(io, stderr, .{
            .argv = &.{ "adb", "-s", serial, "shell", "am", "start", "-n", component },
            .label = "launch Android app",
        });
    }

    if (once) {
        try stdout.writeAll("run completed (--once)\n");
        try stdout.flush();
        return;
    }

    switch (debugger_mode) {
        .jdb => try android_debug.attachJdb(arena, io, stderr, stdout, serial, launch_metadata.app_id),
        .logcat => try android_log_stream.streamAndroidLogs(
            arena,
            io,
            stderr,
            stdout,
            serial,
            launch_metadata.app_id,
            monitor_timeout_seconds,
        ),
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
