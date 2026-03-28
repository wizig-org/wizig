//! Filesystem utility helpers for run/platform modules.
//!
//! This file centralizes path and file mutation helpers so the iOS/Android
//! runners can focus on orchestration logic instead of repeated I/O boilerplate.
const std = @import("std");

const Allocator = std.mem.Allocator;

/// Joins a base path and child segment using the host separator.
pub fn joinPath(allocator: Allocator, base: []const u8, name: []const u8) ![]u8 {
    if (std.mem.eql(u8, base, ".")) {
        return allocator.dupe(u8, name);
    }
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ base, std.fs.path.sep_str, name });
}

/// Returns whether a path exists from the current working directory.
pub fn pathExists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

/// Writes a file atomically with parent path creation.
pub fn writeFileAtomically(io: std.Io, path: []const u8, contents: []const u8) !void {
    var atomic_file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .make_path = true,
        .replace = true,
    });
    defer atomic_file.deinit(io);

    try atomic_file.file.writeStreamingAll(io, contents);
    try atomic_file.replace(io);
}

/// Copies a file only when destination content differs.
pub fn copyFileIfChanged(
    arena: Allocator,
    io: std.Io,
    src_path: []const u8,
    dst_path: []const u8,
) !void {
    const src_bytes = try std.Io.Dir.cwd().readFileAlloc(io, src_path, arena, .limited(128 * 1024 * 1024));
    const dst_bytes = std.Io.Dir.cwd().readFileAlloc(io, dst_path, arena, .limited(128 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => {
            try writeFileAtomically(io, dst_path, src_bytes);
            return;
        },
        else => return err,
    };

    if (std.mem.eql(u8, src_bytes, dst_bytes)) return;
    try writeFileAtomically(io, dst_path, src_bytes);
}
