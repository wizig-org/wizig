//! Plugin import flow for `wizig plugin add`.
const std = @import("std");
const Io = std.Io;

const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");
const process_util = @import("../../../support/process.zig");
const source = @import("source.zig");

/// Adds a plugin from a git source or a local filesystem path.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    source_path: []const u8,
    project_root_raw: []const u8,
) !void {
    const project_root = try path_util.resolveAbsolute(arena, io, project_root_raw);
    const plugins_dir = try path_util.join(arena, project_root, "plugins");
    try fs_util.ensureDir(io, plugins_dir);

    if (source.isLikelyGitSource(source_path)) {
        const base_name = source.repoNameFromSource(source_path);
        const destination = try path_util.join(arena, plugins_dir, base_name);
        _ = process_util.runChecked(
            arena,
            io,
            stderr,
            null,
            &.{ "git", "clone", source_path, destination },
            null,
            "clone plugin repository",
        ) catch {
            try stderr.writeAll("error: failed to clone plugin; check repository access\n");
            return error.PluginFailed;
        };
        try stdout.print("added plugin from git: {s}\n", .{destination});
        return;
    }

    const src_abs = try path_util.resolveAbsolute(arena, io, source_path);
    const base_name = std.fs.path.basename(src_abs);
    const destination = try path_util.join(arena, plugins_dir, base_name);

    fs_util.removeTreeIfExists(io, destination) catch {};
    try fs_util.copyTree(arena, io, src_abs, destination);

    const manifest_path = try path_util.join(arena, destination, "wizig-plugin.json");
    if (!fs_util.pathExists(io, manifest_path)) {
        try stderr.print("error: added plugin has no wizig-plugin.json at '{s}'\n", .{manifest_path});
        return error.PluginFailed;
    }

    try stdout.print("added plugin from path: {s}\n", .{destination});
    try stdout.flush();
}
