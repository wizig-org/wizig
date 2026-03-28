//! Help text renderers for `wizig plugin`.
const std = @import("std");
const Io = std.Io;

/// Writes summary help for `wizig plugin`.
pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Plugin:\n" ++
            "  wizig plugin <command>\n\n" ++
            "Options:\n" ++
            "  -h, --help    Display this help and exit.\n\n" ++
            "Commands:\n" ++
            "  validate      Validate a wizig-plugin.json manifest.\n" ++
            "  sync          Sync installed plugins into a project.\n" ++
            "  add           Add a plugin from a git URL or local path.\n\n" ++
            "Run `wizig plugin <command> --help` for command-specific usage.\n",
    );
}

/// Writes `wizig plugin validate` usage.
pub fn printValidateUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Plugin Validate:\n" ++
            "  wizig plugin validate <wizig-plugin.json>\n\n" ++
            "Options:\n" ++
            "  -h, --help    Display this help and exit.\n\n" ++
            "Arguments:\n" ++
            "  <wizig-plugin.json>    Path to the plugin manifest.\n",
    );
}

/// Writes `wizig plugin sync` usage.
pub fn printSyncUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Plugin Sync:\n" ++
            "  wizig plugin sync [project_root]\n\n" ++
            "Options:\n" ++
            "  -h, --help    Display this help and exit.\n\n" ++
            "Arguments:\n" ++
            "  [project_root]    Project root to sync into. Defaults to current directory.\n",
    );
}

/// Writes `wizig plugin add` usage.
pub fn printAddUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        "Plugin Add:\n" ++
            "  wizig plugin add <git_or_path> [project_root]\n\n" ++
            "Options:\n" ++
            "  -h, --help    Display this help and exit.\n\n" ++
            "Arguments:\n" ++
            "  <git_or_path>    Git URL or local plugin path.\n" ++
            "  [project_root]   Project root to add into. Defaults to current directory.\n",
    );
}

test "printSyncUsage documents optional project root" {
    var out_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out_writer.deinit();

    try printSyncUsage(&out_writer.writer);
    try std.testing.expect(std.mem.indexOf(u8, out_writer.writer.buffered(), "[project_root]") != null);
}
