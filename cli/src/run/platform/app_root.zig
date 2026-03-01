//! App-root path normalization for platform run flows.
//!
//! ## Problem
//! Platform execution code receives run paths from different entrypoints:
//! - app root (`<app>`)
//! - host directory (`<app>/ios`, `<app>/android`)
//!
//! Downstream codegen and FFI preparation must always operate against app root.
//!
//! ## Strategy
//! - Trim trailing separators to avoid dirname edge cases.
//! - Detect whether the provided path already looks like app root (`lib/` exists).
//! - Otherwise fall back to parent directory.
const std = @import("std");

const fs_utils = @import("fs_utils.zig");

/// Resolves app root from a normalized run path.
///
/// Returns:
/// - original path when it already matches an app root
/// - parent path when run was initiated from a host directory
pub fn resolveAppRoot(
    arena: std.mem.Allocator,
    io: std.Io,
    run_project_dir: []const u8,
) ![]const u8 {
    const normalized = try arena.dupe(u8, trimTrailingSeparators(run_project_dir));
    if (looksLikeAppRoot(arena, io, normalized)) return normalized;

    const parent = std.fs.path.dirname(normalized) orelse return normalized;
    if (looksLikeAppRoot(arena, io, parent)) return arena.dupe(u8, parent);

    return arena.dupe(u8, parent);
}

/// Checks whether a path has the expected app-root marker (`lib/`).
fn looksLikeAppRoot(arena: std.mem.Allocator, io: std.Io, path: []const u8) bool {
    const lib_dir = std.fmt.allocPrint(arena, "{s}{s}lib", .{ path, std.fs.path.sep_str }) catch return false;
    return fs_utils.pathExists(io, lib_dir);
}

/// Removes redundant trailing `/` and `\` separators.
///
/// Keeps a single root separator when path length is 1.
fn trimTrailingSeparators(path: []const u8) []const u8 {
    if (path.len <= 1) return path;

    var end = path.len;
    while (end > 1) : (end -= 1) {
        const ch = path[end - 1];
        if (ch != '/' and ch != '\\') break;
    }
    return path[0..end];
}

test "resolveAppRoot keeps app root when lib exists" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    const app_root = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/sample-app", .{tmp.sub_path});
    const lib_dir = try std.fmt.allocPrint(arena, "{s}{s}lib", .{ app_root, std.fs.path.sep_str });
    try std.Io.Dir.cwd().createDirPath(io, lib_dir);

    const resolved = try resolveAppRoot(arena, io, app_root);
    try std.testing.expectEqualStrings(app_root, resolved);
}

test "resolveAppRoot returns parent for host directories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    const app_root = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/sample-app", .{tmp.sub_path});
    const lib_dir = try std.fmt.allocPrint(arena, "{s}{s}lib", .{ app_root, std.fs.path.sep_str });
    const ios_dir = try std.fmt.allocPrint(arena, "{s}{s}ios", .{ app_root, std.fs.path.sep_str });
    try std.Io.Dir.cwd().createDirPath(io, lib_dir);
    try std.Io.Dir.cwd().createDirPath(io, ios_dir);

    const ios_dir_with_slash = try std.fmt.allocPrint(arena, "{s}{s}", .{ ios_dir, std.fs.path.sep_str });
    const resolved = try resolveAppRoot(arena, io, ios_dir_with_slash);
    try std.testing.expectEqualStrings(app_root, resolved);
}
