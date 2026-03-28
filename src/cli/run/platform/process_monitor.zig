//! Watchdog-controlled inherited monitor execution.
//!
//! This facade keeps the public monitor surface stable while the internals are
//! split across smaller helper modules.
const std = @import("std");
const spec = @import("process_monitor/spec.zig");
const runner = @import("process_monitor/runner.zig");

pub const MonitorCommandSpec = spec.MonitorCommandSpec;
pub const LivenessProbe = spec.LivenessProbe;
pub const MonitorWatchdog = spec.MonitorWatchdog;
pub const MonitorStopReason = spec.MonitorStopReason;
pub const MonitoredTerm = spec.MonitoredTerm;

/// Runs an inherited command with watchdog timeout/liveness controls.
pub fn runInheritMonitored(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *std.Io.Writer,
    stdout: *std.Io.Writer,
    spec_arg: MonitorCommandSpec,
    watchdog: MonitorWatchdog,
) !MonitoredTerm {
    return runner.runInheritMonitored(arena, io, stderr, stdout, spec_arg, watchdog);
}

test "process monitor facade compiles" {
    const liveness = @import("process_monitor/liveness.zig");
    const state = @import("process_monitor/state.zig");
    const term = @import("process_monitor/term.zig");

    std.testing.refAllDecls(spec);
    std.testing.refAllDecls(runner);
    std.testing.refAllDecls(liveness);
    std.testing.refAllDecls(state);
    std.testing.refAllDecls(term);
}
