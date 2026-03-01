//! Unified run module shim.
//!
//! This file intentionally remains small and delegates implementation details to
//! `run/unified/*` modules to keep the run pipeline maintainable.
const std = @import("std");
const Io = std.Io;

const root = @import("unified/root.zig");

/// Discovers available targets and runs the selected host flow.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    return root.run(arena, io, parent_environ_map, stderr, stdout, args);
}

/// Writes unified run usage help.
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    return root.printUsage(writer);
}

test {
    std.testing.refAllDecls(@import("unified/options.zig"));
    std.testing.refAllDecls(@import("unified/discovery.zig"));
    std.testing.refAllDecls(@import("unified/logging_codegen.zig"));
}
