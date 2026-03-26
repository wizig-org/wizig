//! Public monitor execution types and command-path helpers.
const std = @import("std");

/// Monitor command invocation parameters.
pub const MonitorCommandSpec = struct {
    argv: []const []const u8,
    cwd_path: ?[]const u8 = null,
    environ_map: ?*const std.process.Environ.Map = null,
    label: []const u8,
};

/// App liveness probe settings used by monitor watchdog execution.
pub const LivenessProbe = struct {
    spec: MonitorCommandSpec,
    required_substring: ?[]const u8 = null,
};

/// Watchdog controls for long-running monitor commands.
pub const MonitorWatchdog = struct {
    timeout_seconds: ?u64 = null,
    poll_interval_seconds: u64 = 1,
    liveness_probe: ?LivenessProbe = null,
};

/// Reason why monitored command execution completed.
pub const MonitorStopReason = enum {
    exited,
    interrupted,
    timeout,
    app_liveness_lost,
};

/// Result for monitored inherited command execution.
pub const MonitoredTerm = struct {
    term: std.process.Child.Term,
    stop_reason: MonitorStopReason,
};

/// Converts nullable cwd string into `Child.Cwd` representation.
pub fn childCwd(path: ?[]const u8) std.process.Child.Cwd {
    return if (path) |p| .{ .path = p } else .inherit;
}

test "childCwd returns inherit when cwd is omitted" {
    try std.testing.expect(switch (childCwd(null)) {
        .inherit => true,
        else => false,
    });
}

test "childCwd returns path when cwd is present" {
    const cwd = childCwd("/tmp/example");
    switch (cwd) {
        .path => |path| try std.testing.expect(std.mem.eql(u8, path, "/tmp/example")),
        else => return error.TestUnexpectedResult,
    }
}
