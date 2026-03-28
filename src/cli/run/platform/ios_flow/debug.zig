//! Debugger attachment helpers for iOS runs.
const std = @import("std");
const Io = std.Io;

const process = @import("../process_supervisor.zig");
const types = @import("../types.zig");

/// Attaches the requested debugger or prints the no-debugger completion message.
pub fn attachDebuggerIfNeeded(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    debugger_mode: types.DebuggerMode,
    pid: u64,
) !void {
    switch (debugger_mode) {
        .lldb => {
            const attach_command = try std.fmt.allocPrint(arena, "process attach --pid {d}", .{pid});
            try stdout.writeAll("attaching lldb (exit lldb to stop wizig run)...\n");
            try stdout.flush();
            try process.runInheritChecked(io, stderr, .{ .argv = &.{ "lldb", "-o", attach_command, "-o", "continue" }, .label = "attach lldb to iOS app" });
        },
        .none => {
            try stdout.writeAll("app launched without debugger\n");
            try stdout.flush();
        },
        else => {
            try stderr.writeAll("error: selected debugger is not valid for iOS\n");
            return error.RunFailed;
        },
    }
}
