//! Code generation preflight for platform run commands.
//!
//! The platform runner reuses codegen logic so host-side bindings remain in
//! sync with current app sources before build/install operations.
const std = @import("std");
const Io = std.Io;

const app_root = @import("app_root.zig");
const logging_codegen = @import("../unified/logging_codegen.zig");

/// Ensures app bindings are generated before platform build execution.
pub fn runCodegenPreflight(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    host_project_dir: []const u8,
) !void {
    const app_root_path = try app_root.resolveAppRoot(arena, io, host_project_dir);
    var discarded_log_lines = std.ArrayList(u8).empty;
    defer discarded_log_lines.deinit(arena);
    try logging_codegen.runCodegenPreflight(arena, io, stderr, stdout, app_root_path, &discarded_log_lines);
}
