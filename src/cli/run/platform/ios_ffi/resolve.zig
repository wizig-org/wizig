//! iOS FFI library path resolution helpers.
//!
//! The run pipeline uses this lookup when a prebuilt framework or archive is
//! supplied via environment or when falling back to `zig-out`.
const std = @import("std");

const fs_utils = @import("../fs_utils.zig");

/// Resolves an existing iOS FFI library path from the environment or `zig-out`.
pub fn resolveIosFfiLibraryPath(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
) !?[]const u8 {
    if (parent_environ_map.get("WIZIG_FFI_LIB")) |raw_path| {
        if (std.fs.path.isAbsolute(raw_path)) {
            if (fs_utils.pathExists(io, raw_path)) return try arena.dupe(u8, raw_path);
        } else {
            const cwd = try std.process.currentPathAlloc(io, arena);
            const resolved = try std.fs.path.resolve(arena, &.{ cwd, raw_path });
            if (fs_utils.pathExists(io, resolved)) return resolved;
        }
    }

    const cwd = try std.process.currentPathAlloc(io, arena);
    const framework_guess = try std.fs.path.resolve(arena, &.{ cwd, "zig-out", "lib", "WizigFFI.framework", "WizigFFI" });
    if (fs_utils.pathExists(io, framework_guess)) return framework_guess;
    const static_guess = try std.fs.path.resolve(arena, &.{ cwd, "zig-out", "lib", "libWizigFFI.a" });
    if (fs_utils.pathExists(io, static_guess)) return static_guess;
    return null;
}
