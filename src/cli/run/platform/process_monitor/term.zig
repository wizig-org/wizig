//! Child termination helpers shared by monitor and supervisor logic.
const std = @import("std");

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

test "termIsSuccess only accepts zero exit codes" {
    try std.testing.expect(termIsSuccess(.{ .exited = 0 }));
    try std.testing.expect(!termIsSuccess(.{ .exited = 1 }));
    try std.testing.expect(!termIsSuccess(.{ .signal = .INT }));
}

test "termIsInterrupted only accepts interrupt signal" {
    try std.testing.expect(termIsInterrupted(.{ .signal = .INT }));
    try std.testing.expect(!termIsInterrupted(.{ .signal = .KILL }));
    try std.testing.expect(!termIsInterrupted(.{ .exited = 0 }));
}
