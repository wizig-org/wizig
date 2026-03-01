//! Toolchain lock-file creation for `wizig create`.
//!
//! This module bridges scaffold creation with centralized toolchain governance
//! by loading manifest policy and writing `.wizig/toolchain.lock.json`.
const std = @import("std");
const Io = std.Io;

const toolchains = @import("../../support/toolchains/root.zig");

/// Writes a project lock file using policy from the resolved SDK/workspace root.
///
/// This step runs after scaffold+codegen so generated projects always include
/// a reproducibility marker tied to the manifest and host tool versions.
pub fn writeProjectLock(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    sdk_root: []const u8,
    project_root: []const u8,
) !void {
    const manifest = toolchains.manifest.loadFromRoot(arena, io, stderr, sdk_root) catch |err| {
        try stderr.print("error: failed to load toolchains policy: {s}\n", .{@errorName(err)});
        return error.CreateFailed;
    };

    toolchains.lockfile.writeProjectLock(arena, io, project_root, manifest) catch |err| {
        try stderr.print("error: failed to write .wizig/toolchain.lock.json: {s}\n", .{@errorName(err)});
        return error.CreateFailed;
    };

    try stdout.writeAll("wrote .wizig/toolchain.lock.json\n");
}
