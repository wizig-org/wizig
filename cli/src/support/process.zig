const std = @import("std");
const Io = std.Io;

pub const CommandResult = std.process.RunResult;

pub fn runCapture(
    arena: std.mem.Allocator,
    io: std.Io,
    cwd_path: ?[]const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !CommandResult {
    return std.process.run(arena, io, .{
        .argv = argv,
        .cwd = if (cwd_path) |path| .{ .path = path } else .inherit,
        .environ_map = environ_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
}

pub fn runChecked(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    cwd_path: ?[]const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
    description: []const u8,
) !CommandResult {
    const result = runCapture(arena, io, cwd_path, argv, environ_map) catch |err| {
        try stderr.print("error: failed to spawn '{s}' while trying to {s}: {s}\n", .{ argv[0], description, @errorName(err) });
        return err;
    };

    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!ok) {
        if (result.stdout.len > 0) {
            try stderr.print("{s}\n", .{result.stdout});
        }
        if (result.stderr.len > 0) {
            try stderr.print("{s}\n", .{result.stderr});
        }
        return error.CommandFailed;
    }
    return result;
}

pub fn commandExists(
    arena: std.mem.Allocator,
    io: std.Io,
    name: []const u8,
) bool {
    const result = runCapture(arena, io, null, &.{ "which", name }, null) catch return false;
    return switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
}
