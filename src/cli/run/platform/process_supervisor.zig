//! Centralized process supervision for the run pipeline.
//!
//! This module is the single execution surface for child processes used by
//! platform runners. It standardizes spawn/capture semantics, exit handling,
//! and diagnostics so terminal output behavior stays consistent across iOS and
//! Android flows.
const std = @import("std");
const Io = std.Io;

const monitor = @import("process_monitor.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;

/// Alias for captured process output.
pub const CommandResult = std.process.RunResult;

/// Capture size limits for stdout/stderr.
pub const CaptureLimits = struct {
    stdout_bytes: usize = 32 * 1024 * 1024,
    stderr_bytes: usize = 32 * 1024 * 1024,
};

/// Parameters that describe a single child process invocation.
pub const CommandSpec = struct {
    argv: []const []const u8,
    cwd_path: ?[]const u8 = null,
    environ_map: ?*const std.process.Environ.Map = null,
    label: []const u8,
};

/// Monitor command spec for inherited watchdog execution.
pub const MonitorCommandSpec = monitor.MonitorCommandSpec;

/// App liveness probe settings used by monitor watchdog execution.
pub const LivenessProbe = monitor.LivenessProbe;

/// Watchdog controls for long-running monitor commands.
pub const MonitorWatchdog = monitor.MonitorWatchdog;

/// Reason why monitored command execution completed.
pub const MonitorStopReason = monitor.MonitorStopReason;

/// Result for monitored inherited command execution.
pub const MonitoredTerm = monitor.MonitoredTerm;

/// Executes a child process with captured stdout/stderr.
///
/// This is intentionally used for short-lived commands whose output is parsed.
/// For long-running monitors, use `runInheritTerm` or `runInheritMonitored`.
pub fn runCapture(
    arena: Allocator,
    io: std.Io,
    spec: CommandSpec,
    limits: CaptureLimits,
) !CommandResult {
    return std.process.run(arena, io, .{
        .argv = spec.argv,
        .cwd = childCwd(spec.cwd_path),
        .environ_map = spec.environ_map,
        .stdout_limit = .limited(limits.stdout_bytes),
        .stderr_limit = .limited(limits.stderr_bytes),
    });
}

/// Executes a captured command and returns `RunFailed` on non-zero exit.
///
/// On failure, this routine prints both captured streams so users retain full
/// command context without hunting in intermediate logs.
pub fn runCaptureChecked(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    spec: CommandSpec,
    limits: CaptureLimits,
) !CommandResult {
    const result = runCapture(arena, io, spec, limits) catch |err| {
        try stderr.print(
            "error: failed to spawn command for {s}: {s}\n",
            .{ spec.label, @errorName(err) },
        );
        try stderr.flush();
        return types.RunError.RunFailed;
    };

    if (!termIsSuccess(result.term)) {
        try printCommandFailure(stderr, spec, result);
        return types.RunError.RunFailed;
    }
    return result;
}

/// Spawns a child process with inherited stdio and waits for termination.
///
/// This is used for interactive processes or log streams where immediate
/// terminal visibility is more useful than buffered capture.
pub fn runInheritTerm(
    io: std.Io,
    stderr: *Io.Writer,
    spec: CommandSpec,
) !std.process.Child.Term {
    var child = std.process.spawn(io, .{
        .argv = spec.argv,
        .cwd = childCwd(spec.cwd_path),
        .environ_map = spec.environ_map,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        try stderr.print(
            "error: failed to spawn command for {s}: {s}\n",
            .{ spec.label, @errorName(err) },
        );
        try stderr.flush();
        return types.RunError.RunFailed;
    };
    defer child.kill(io);

    return child.wait(io) catch |err| {
        try stderr.print(
            "error: command wait failed for {s}: {s}\n",
            .{ spec.label, @errorName(err) },
        );
        try stderr.flush();
        return types.RunError.RunFailed;
    };
}

/// Runs an inherited command with watchdog timeout/liveness controls.
///
/// This delegates to `process_monitor.zig` so monitor-specific logic remains
/// isolated from short-lived command execution behavior.
pub fn runInheritMonitored(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    spec: MonitorCommandSpec,
    watchdog: MonitorWatchdog,
) !MonitoredTerm {
    return monitor.runInheritMonitored(arena, io, stderr, stdout, spec, watchdog);
}

/// Runs an inherited command and fails on non-zero termination.
///
/// This helper keeps error reporting consistent for build/install phases while
/// preserving direct terminal output streaming from child tools.
pub fn runInheritChecked(
    io: std.Io,
    stderr: *Io.Writer,
    spec: CommandSpec,
) !void {
    const term = try runInheritTerm(io, stderr, spec);
    if (!termIsSuccess(term)) {
        try stderr.print(
            "error: command failed for {s} ({s})\n",
            .{ spec.label, termLabel(term) },
        );
        try stderr.flush();
        return types.RunError.RunFailed;
    }
}

/// Returns whether a process terminated with successful exit code.
pub fn termIsSuccess(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

/// Returns whether a process terminated due to user interrupt signal.
pub fn termIsInterrupted(term: std.process.Child.Term) bool {
    return switch (term) {
        .signal => |sig| sig == .INT,
        else => false,
    };
}

/// Returns a compact label for a child termination state.
pub fn termLabel(term: std.process.Child.Term) []const u8 {
    return switch (term) {
        .exited => "exited",
        .signal => "signal",
        .stopped => "stopped",
        .unknown => "unknown",
    };
}

/// Formats and prints detailed command failure diagnostics.
fn printCommandFailure(
    stderr: *Io.Writer,
    spec: CommandSpec,
    result: CommandResult,
) !void {
    try stderr.print(
        "error: command failed for {s}: {s} ({s})\n",
        .{ spec.label, spec.argv[0], termLabel(result.term) },
    );
    if (result.stdout.len > 0) {
        try stderr.print("{s}\n", .{result.stdout});
    }
    if (result.stderr.len > 0) {
        try stderr.print("{s}\n", .{result.stderr});
    }
    try stderr.flush();
}

/// Converts nullable cwd string into `Child.Cwd` representation.
fn childCwd(path: ?[]const u8) std.process.Child.Cwd {
    return if (path) |p| .{ .path = p } else .inherit;
}
