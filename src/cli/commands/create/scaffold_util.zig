//! Shared low-level utilities for scaffold generation.
//!
//! These functions isolate process execution and filesystem write patterns used
//! by `wizig create` so orchestration code remains concise.
const std = @import("std");
const Io = std.Io;

/// Joins `base` and `name` using the platform path separator.
///
/// Special-cases `.` to avoid prefixing the generated path with `./` which
/// keeps command output and generated metadata stable.
pub fn joinPath(allocator: std.mem.Allocator, base: []const u8, name: []const u8) ![]u8 {
    if (std.mem.eql(u8, base, ".")) {
        return allocator.dupe(u8, name);
    }
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ base, std.fs.path.sep_str, name });
}

/// Writes `contents` to `path` atomically.
///
/// The write uses a temporary file and replace operation so partial writes are
/// never observed by downstream build or codegen steps.
pub fn writeFileAtomically(io: std.Io, path: []const u8, contents: []const u8) !void {
    var atomic_file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .make_path = true,
        .replace = true,
    });
    defer atomic_file.deinit(io);

    try atomic_file.file.writeStreamingAll(io, contents);
    try atomic_file.replace(io);
}

/// Runs a command and surfaces non-zero exit output through `stderr`.
///
/// This helper centralizes command error rendering so scaffold command failures
/// are consistent and actionable.
pub fn runCommand(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    cwd_path: []const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !void {
    const result = std.process.run(arena, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd_path },
        .environ_map = environ_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch |err| {
        try stderr.print("error: failed to spawn '{s}': {s}\n", .{ argv[0], @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const success = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };

    if (!success) {
        if (result.stdout.len > 0) {
            try stderr.print("{s}\n", .{result.stdout});
        }
        if (result.stderr.len > 0) {
            try stderr.print("{s}\n", .{result.stderr});
        }
        try stderr.flush();
        return error.CreateFailed;
    }
}
