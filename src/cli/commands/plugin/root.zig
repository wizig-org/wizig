//! Public `wizig plugin` entrypoint.
//!
//! The command implementation lives under `commands/plugin/root/` so the
//! top-level module stays small and preserves the existing CLI surface.
const std = @import("std");
const Io = std.Io;

const dispatch = @import("root/dispatch.zig");

/// Executes plugin subcommands.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    return dispatch.run(arena, io, stderr, stdout, args);
}

/// Writes the plugin command usage block used by the top-level help output.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try dispatch.printUsage(writer);
}

test {
    _ = @import("root/dispatch.zig");
    _ = @import("root/dispatch_tests.zig");
}
