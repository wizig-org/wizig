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
    try writer.writeAll(
        "Plugin:\n" ++
            "  wizig plugin validate <wizig-plugin.json>\n" ++
            "  wizig plugin sync [project_root]\n" ++
            "  wizig plugin add <git_or_path> [project_root]\n" ++
            "\n",
    );
}

test {
    _ = @import("root/dispatch.zig");
}
