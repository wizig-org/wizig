//! Android platform run orchestration.
//!
//! This facade keeps the public entrypoint stable while delegating the Android
//! run pipeline to smaller stage-specific modules.
const std = @import("std");
const Io = std.Io;

const pipeline = @import("android_flow/pipeline.zig");

/// Executes the full Android run pipeline.
pub fn runAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: @import("types.zig").RunOptions,
) !void {
    try pipeline.runAndroid(arena, io, parent_environ_map, stderr, stdout, options);
}

test {
    std.testing.refAllDecls(@import("android_flow/build.zig"));
    std.testing.refAllDecls(@import("android_flow/launch.zig"));
    std.testing.refAllDecls(@import("android_flow/metadata.zig"));
    std.testing.refAllDecls(@import("android_flow/pipeline.zig"));
    std.testing.refAllDecls(@import("android_flow/selection.zig"));
}
