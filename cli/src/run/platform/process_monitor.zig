//! Watchdog-controlled inherited monitor execution.
//!
//! This module owns long-running monitor behavior (timeout and app-liveness
//! driven shutdown) so the main process supervisor remains focused on generic
//! command execution.
const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

const types = @import("types.zig");

const Allocator = std.mem.Allocator;

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

/// Runs an inherited command with watchdog timeout/liveness controls.
///
/// This routine is intended for terminal monitors (`logcat`, simulator console)
/// that should stop automatically when the app exits or a timeout is reached.
pub fn runInheritMonitored(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    spec: MonitorCommandSpec,
    watchdog: MonitorWatchdog,
) !MonitoredTerm {
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

    var wait_state = WaitState{};
    var wait_ctx = WaitThreadContext{
        .child = &child,
        .io = io,
        .state = &wait_state,
    };
    var wait_thread = std.Thread.spawn(.{}, waitForChildThread, .{&wait_ctx}) catch |err| {
        try stderr.print("error: failed to spawn monitor wait thread for {s}: {s}\n", .{ spec.label, @errorName(err) });
        try stderr.flush();
        child.kill(io);
        return types.RunError.RunFailed;
    };
    defer wait_thread.join();

    const child_id = child.id;
    const started_at = std.Io.Timestamp.now(io, .boot);
    const poll_seconds = if (watchdog.poll_interval_seconds == 0) 1 else watchdog.poll_interval_seconds;

    while (true) {
        const snapshot = readWaitState(&wait_state);
        if (snapshot.done) {
            if (snapshot.wait_failed or snapshot.term == null) {
                try stderr.print("error: command wait failed for {s}\n", .{spec.label});
                try stderr.flush();
                return types.RunError.RunFailed;
            }
            return .{
                .term = snapshot.term.?,
                .stop_reason = if (termIsInterrupted(snapshot.term.?)) .interrupted else .exited,
            };
        }

        if (watchdog.timeout_seconds) |seconds| {
            const now = std.Io.Timestamp.now(io, .boot);
            const elapsed = started_at.durationTo(now).toSeconds();
            if (elapsed >= @as(i64, @intCast(seconds))) {
                try stdout.print("monitor timeout reached ({d}s), stopping {s}\n", .{ seconds, spec.label });
                try stdout.flush();
                terminateMonitoredChild(io, child_id, &wait_state);
                const final_snapshot = readWaitState(&wait_state);
                return .{
                    .term = final_snapshot.term orelse .{ .unknown = 0 },
                    .stop_reason = .timeout,
                };
            }
        }

        if (watchdog.liveness_probe) |probe| {
            if (!probeAppLiveness(arena, io, probe)) {
                try stdout.print("app liveness check ended, stopping {s}\n", .{spec.label});
                try stdout.flush();
                terminateMonitoredChild(io, child_id, &wait_state);
                const final_snapshot = readWaitState(&wait_state);
                return .{
                    .term = final_snapshot.term orelse .{ .unknown = 0 },
                    .stop_reason = .app_liveness_lost,
                };
            }
        }

        std.Io.sleep(io, .fromSeconds(@intCast(poll_seconds)), .awake) catch {};
    }
}

const WaitState = struct {
    mutex: std.atomic.Mutex = .unlocked,
    done: bool = false,
    wait_failed: bool = false,
    term: ?std.process.Child.Term = null,
};

const WaitStateSnapshot = struct {
    done: bool,
    wait_failed: bool,
    term: ?std.process.Child.Term,
};

const WaitThreadContext = struct {
    child: *std.process.Child,
    io: std.Io,
    state: *WaitState,
};

fn waitForChildThread(ctx: *WaitThreadContext) void {
    const term = ctx.child.wait(ctx.io) catch {
        lockState(ctx.state);
        ctx.state.wait_failed = true;
        ctx.state.done = true;
        ctx.state.mutex.unlock();
        return;
    };

    lockState(ctx.state);
    ctx.state.term = term;
    ctx.state.done = true;
    ctx.state.mutex.unlock();
}

fn terminateMonitoredChild(io: std.Io, child_id: ?std.process.Child.Id, state: *WaitState) void {
    if (child_id == null) return;
    sendChildSignal(child_id.?, .INT);
    if (waitForChildState(io, state, 2)) return;
    sendChildSignal(child_id.?, .KILL);
    _ = waitForChildState(io, state, 5);
}

fn waitForChildState(io: std.Io, state: *WaitState, timeout_seconds: u64) bool {
    const started_at = std.Io.Timestamp.now(io, .boot);
    while (true) {
        if (readWaitState(state).done) return true;
        const elapsed = started_at.durationTo(std.Io.Timestamp.now(io, .boot)).toSeconds();
        if (elapsed >= @as(i64, @intCast(timeout_seconds))) return false;
        std.Io.sleep(io, .fromMilliseconds(200), .awake) catch {};
    }
}

fn sendChildSignal(child_id: std.process.Child.Id, signal: std.posix.SIG) void {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return;
    const pid: std.posix.pid_t = @intCast(child_id);
    std.posix.kill(pid, signal) catch {};
}

fn readWaitState(state: *WaitState) WaitStateSnapshot {
    lockState(state);
    defer state.mutex.unlock();
    return .{
        .done = state.done,
        .wait_failed = state.wait_failed,
        .term = state.term,
    };
}

fn lockState(state: *WaitState) void {
    while (!state.mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}

fn probeAppLiveness(arena: Allocator, io: std.Io, probe: LivenessProbe) bool {
    _ = arena;
    var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    const result = std.process.run(scratch, io, .{
        .argv = probe.spec.argv,
        .cwd = childCwd(probe.spec.cwd_path),
        .environ_map = probe.spec.environ_map,
        .stdout_limit = .limited(128 * 1024),
        .stderr_limit = .limited(128 * 1024),
    }) catch {
        return false;
    };
    return livenessProbeSatisfied(probe, result);
}

fn livenessProbeSatisfied(probe: LivenessProbe, result: std.process.RunResult) bool {
    if (!termIsSuccess(result.term)) return false;
    if (probe.required_substring) |needle| {
        if (std.mem.indexOf(u8, result.stdout, needle) != null) return true;
        if (std.mem.indexOf(u8, result.stderr, needle) != null) return true;
        return false;
    }
    return true;
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

fn childCwd(path: ?[]const u8) std.process.Child.Cwd {
    return if (path) |p| .{ .path = p } else .inherit;
}

test "livenessProbeSatisfied accepts success without token requirement" {
    var stdout_text = [_]u8{ 'a', 'l', 'i', 'v', 'e' };
    const probe = LivenessProbe{
        .spec = .{ .argv = &.{ "echo" }, .label = "probe" },
    };
    const result: std.process.RunResult = .{
        .term = .{ .exited = 0 },
        .stdout = stdout_text[0..],
        .stderr = stdout_text[0..0],
    };
    try std.testing.expect(livenessProbeSatisfied(probe, result));
}

test "livenessProbeSatisfied requires substring when configured" {
    var stdout_ok = [_]u8{ 'h', 'a', 's', ' ', 't', 'o', 'k', 'e', 'n' };
    var stdout_missing = [_]u8{ 'n', 'o', 'p', 'e' };
    const probe = LivenessProbe{
        .spec = .{ .argv = &.{ "echo" }, .label = "probe" },
        .required_substring = "token",
    };
    const ok: std.process.RunResult = .{
        .term = .{ .exited = 0 },
        .stdout = stdout_ok[0..],
        .stderr = stdout_ok[0..0],
    };
    const missing: std.process.RunResult = .{
        .term = .{ .exited = 0 },
        .stdout = stdout_missing[0..],
        .stderr = stdout_missing[0..0],
    };
    try std.testing.expect(livenessProbeSatisfied(probe, ok));
    try std.testing.expect(!livenessProbeSatisfied(probe, missing));
}
