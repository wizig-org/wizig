//! Shared state for the iOS run orchestration pipeline.
const std = @import("std");
const Io = std.Io;

const types = @import("../types.zig");

/// Shared iOS run state passed between selection and launch phases.
pub const RunContext = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
    xcode_project: []const u8,
    scheme: []const u8,
    debugger_mode: types.DebuggerMode,
};
