//! Validation flow for `wizig plugin validate`.
const std = @import("std");
const Io = std.Io;

const wizig_core = @import("wizig_core");

/// Reads a plugin manifest, validates it, and prints a summary.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    file_path: []const u8,
) !void {
    const manifest_text = std.Io.Dir.cwd().readFileAlloc(io, file_path, arena, .limited(1024 * 1024)) catch |err| {
        try stderr.print("error: failed to read '{s}': {s}\n", .{ file_path, @errorName(err) });
        return error.PluginFailed;
    };

    var manifest = wizig_core.PluginManifest.parse(arena, manifest_text) catch |err| {
        try stderr.print("error: invalid plugin manifest '{s}': {s}\n", .{ file_path, @errorName(err) });
        return error.PluginFailed;
    };
    defer manifest.deinit(arena);

    try stdout.print(
        "valid plugin '{s}' version {s} schema v{d} (api {d}) with {d} capabilities\n",
        .{ manifest.id, manifest.version, manifest.schema_version, manifest.api_version, manifest.capabilities.len },
    );
    try stdout.flush();
}
