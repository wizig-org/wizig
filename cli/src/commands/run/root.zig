const std = @import("std");
const Io = std.Io;
const run_impl = @import("../../run.zig");

pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    return run_impl.run(arena, io, env_map, stderr, stdout, args);
}

pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try run_impl.printUsage(writer);
}
