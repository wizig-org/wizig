//! Toolchain command discovery helpers.
//!
//! These helpers provide lightweight capability checks used to validate
//! debugger/tool availability before entering platform-specific flows.
const std = @import("std");

const supervisor = @import("process_supervisor.zig");

/// Returns true when `command_name` is discoverable via `which`.
pub fn commandExists(
    arena: std.mem.Allocator,
    io: std.Io,
    command_name: []const u8,
) bool {
    const result = supervisor.runCapture(arena, io, .{
        .argv = &.{ "which", command_name },
        .label = "discover command",
    }, .{}) catch return false;
    return supervisor.termIsSuccess(result.term) and std.mem.trim(u8, result.stdout, " \t\r\n").len > 0;
}
