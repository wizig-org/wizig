//! Monitored inherited-process execution with timeout and liveness controls.
const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

const liveness = @import("liveness.zig");
const spec = @import("spec.zig");
const state = @import("state.zig");
const term = @import("term.zig");
const types = @import("../types.zig");

const Allocator = std.mem.Allocator;

/// Runs an inherited command with watchdog timeout/liveness controls.
pub fn runInheritMonitored(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    monitor_spec: spec.MonitorCommandSpec,
    watchdog: spec.MonitorWatchdog,
) !spec.MonitoredTerm {
    _ = arena;
    var child = std.process.spawn(io, .{
        .argv = monitor_spec.argv,
        .cwd = spec.childCwd(monitor_spec.cwd_path),
        .environ_map = monitor_spec.environ_map,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        try stderr.print(
            "error: failed to spawn command for {s}: {s}\n",
            .{ monitor_spec.label, @errorName(err) },
        );
        try stderr.flush();
        return types.RunError.RunFailed;
    };

    var wait_state = state.WaitState{};
    var wait_ctx = state.WaitThreadContext{
        .child = &child,
        .io = io,
        .state = &wait_state,
    };
    var wait_thread = std.Thread.spawn(.{}, state.waitForChildThread, .{&wait_ctx}) catch |err| {
        try stderr.print(
            "error: failed to spawn monitor wait thread for {s}: {s}\n",
            .{ monitor_spec.label, @errorName(err) },
        );
        try stderr.flush();
        child.kill(io);
        return types.RunError.RunFailed;
    };
    defer wait_thread.join();

    const child_id = child.id;
    const started_at = std.Io.Timestamp.now(io, .boot);
    const poll_seconds = effectivePollIntervalSeconds(watchdog.poll_interval_seconds);

    while (true) {
        const snapshot = state.readWaitState(&wait_state);
        if (snapshot.done) {
            if (snapshot.wait_failed or snapshot.term == null) {
                try stderr.print("error: command wait failed for {s}\n", .{monitor_spec.label});
                try stderr.flush();
                return types.RunError.RunFailed;
            }
            return .{
                .term = snapshot.term.?,
                .stop_reason = if (term.termIsInterrupted(snapshot.term.?)) .interrupted else .exited,
            };
        }

        if (watchdog.timeout_seconds) |seconds| {
            const now = std.Io.Timestamp.now(io, .boot);
            const elapsed = started_at.durationTo(now).toSeconds();
            if (elapsed >= @as(i64, @intCast(seconds))) {
                try stdout.print("monitor timeout reached ({d}s), stopping {s}\n", .{ seconds, monitor_spec.label });
                try stdout.flush();
                terminateMonitoredChild(io, child_id, &wait_state);
                const final_snapshot = state.readWaitState(&wait_state);
                return .{
                    .term = final_snapshot.term orelse .{ .unknown = 0 },
                    .stop_reason = .timeout,
                };
            }
        }

        if (watchdog.liveness_probe) |probe| {
            if (!liveness.probeAppLiveness(io, probe)) {
                try stdout.print("app liveness check ended, stopping {s}\n", .{monitor_spec.label});
                try stdout.flush();
                terminateMonitoredChild(io, child_id, &wait_state);
                const final_snapshot = state.readWaitState(&wait_state);
                return .{
                    .term = final_snapshot.term orelse .{ .unknown = 0 },
                    .stop_reason = .app_liveness_lost,
                };
            }
        }

        std.Io.sleep(io, .fromSeconds(@intCast(poll_seconds)), .awake) catch {};
    }
}

fn terminateMonitoredChild(io: std.Io, child_id: ?std.process.Child.Id, wait_state: *state.WaitState) void {
    if (child_id == null) return;
    sendChildSignal(child_id.?, .INT);
    if (state.waitForChildState(io, wait_state, 2)) return;
    sendChildSignal(child_id.?, .KILL);
    _ = state.waitForChildState(io, wait_state, 5);
}

fn sendChildSignal(child_id: std.process.Child.Id, signal: std.posix.SIG) void {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return;
    const pid: std.posix.pid_t = @intCast(child_id);
    std.posix.kill(pid, signal) catch {};
}

pub fn effectivePollIntervalSeconds(seconds: u64) u64 {
    return if (seconds == 0) 1 else seconds;
}

test "effectivePollIntervalSeconds defaults zero to one" {
    try std.testing.expectEqual(@as(u64, 1), effectivePollIntervalSeconds(0));
    try std.testing.expectEqual(@as(u64, 5), effectivePollIntervalSeconds(5));
}
