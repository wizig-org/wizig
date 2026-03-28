//! `wizig create` command parser and dispatch.
const std = @import("std");
const Io = std.Io;

const options = @import("options.zig");
const scaffold = @import("scaffold.zig");

/// Parses create options and delegates scaffold generation.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    const request = options.parseCreateRequest(arena, stderr, args) catch {
        return error.CreateFailed;
    };

    if (request == null) {
        try options.printUsage(stdout);
        try stdout.flush();
        return;
    }

    const parsed = request.?;
    try scaffold.createApp(
        arena,
        io,
        env_map,
        stderr,
        stdout,
        parsed.app_name,
        parsed.destination_dir,
        parsed.platforms,
        parsed.sdk_root,
        parsed.force_host_overwrite,
    );
}

/// Writes usage help for the create command.
pub fn printUsage(writer: *Io.Writer) !void {
    try options.printUsage(writer);
}
