//! Synchronization state for monitored child process wait handling.
const std = @import("std");

/// Shared state used by the wait thread and watchdog loop.
pub const WaitState = struct {
    mutex: std.atomic.Mutex = .unlocked,
    done: bool = false,
    wait_failed: bool = false,
    term: ?std.process.Child.Term = null,
};

/// Immutable snapshot of the shared wait state.
pub const WaitStateSnapshot = struct {
    done: bool,
    wait_failed: bool,
    term: ?std.process.Child.Term,
};

/// Wait-thread context used to watch the inherited child process.
pub const WaitThreadContext = struct {
    child: *std.process.Child,
    io: std.Io,
    state: *WaitState,
};

/// Waits for the child process on a helper thread and records the result.
pub fn waitForChildThread(ctx: *WaitThreadContext) void {
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

/// Returns a consistent snapshot of the wait state under lock.
pub fn readWaitState(state: *WaitState) WaitStateSnapshot {
    lockState(state);
    defer state.mutex.unlock();
    return .{
        .done = state.done,
        .wait_failed = state.wait_failed,
        .term = state.term,
    };
}

/// Waits for a child state transition until the timeout elapses.
pub fn waitForChildState(io: std.Io, state: *WaitState, timeout_seconds: u64) bool {
    const started_at = std.Io.Timestamp.now(io, .boot);
    while (true) {
        if (readWaitState(state).done) return true;
        const elapsed = started_at.durationTo(std.Io.Timestamp.now(io, .boot)).toSeconds();
        if (elapsed >= @as(i64, @intCast(timeout_seconds))) return false;
        std.Io.sleep(io, .fromMilliseconds(200), .awake) catch {};
    }
}

fn lockState(state: *WaitState) void {
    while (!state.mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}
