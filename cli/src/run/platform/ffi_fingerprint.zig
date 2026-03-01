//! Fingerprint computation for cached FFI build artifacts.
//!
//! The run pipeline caches built FFI outputs in `/tmp` based on source content
//! and target descriptor. This module provides deterministic hashing across core,
//! generated, and app Zig inputs.
const std = @import("std");

const fs_utils = @import("fs_utils.zig");
const text_utils = @import("text_utils.zig");

/// Cache key version for iOS simulator FFI artifacts.
pub const ios_ffi_cache_version = "wizig-ios-ffi-cache-v2";

/// Cache key version for Android FFI artifacts.
pub const android_ffi_cache_version = "wizig-android-ffi-cache-v2";

/// Computes a stable SHA-256 fingerprint for an FFI build input set.
pub fn computeFfiFingerprint(
    arena: std.mem.Allocator,
    io: std.Io,
    version: []const u8,
    target_descriptor: []const u8,
    root_source: []const u8,
    core_source: []const u8,
    app_fingerprint_roots: []const []const u8,
) ![]const u8 {
    const root_bytes = std.Io.Dir.cwd().readFileAlloc(io, root_source, arena, .limited(8 * 1024 * 1024)) catch |err| {
        return switch (err) {
            error.FileNotFound => error.RunFailed,
            else => err,
        };
    };
    const core_bytes = std.Io.Dir.cwd().readFileAlloc(io, core_source, arena, .limited(8 * 1024 * 1024)) catch |err| {
        return switch (err) {
            error.FileNotFound => error.RunFailed,
            else => err,
        };
    };

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(version);
    hasher.update(&[_]u8{0});
    hasher.update(target_descriptor);
    hasher.update(&[_]u8{0});
    hasher.update(root_source);
    hasher.update(&[_]u8{0});
    hasher.update(root_bytes);
    hasher.update(&[_]u8{0});
    hasher.update(core_source);
    hasher.update(&[_]u8{0});
    hasher.update(core_bytes);
    for (app_fingerprint_roots) |root| {
        try appendZigTreeFingerprint(arena, io, &hasher, root);
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return arena.dupe(u8, &hex);
}

fn appendZigTreeFingerprint(
    arena: std.mem.Allocator,
    io: std.Io,
    hasher: *std.crypto.hash.sha2.Sha256,
    root_dir: []const u8,
) !void {
    if (!fs_utils.pathExists(io, root_dir)) return;

    const rel_paths = try collectZigFilesRecursivelySorted(arena, io, root_dir);
    hasher.update(&[_]u8{0});
    hasher.update(root_dir);
    hasher.update(&[_]u8{0});
    for (rel_paths) |rel_path| {
        const abs_path = try std.fmt.allocPrint(arena, "{s}{s}{s}", .{ root_dir, std.fs.path.sep_str, rel_path });
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, abs_path, arena, .limited(8 * 1024 * 1024)) catch |err| {
            return switch (err) {
                error.FileNotFound => error.RunFailed,
                else => err,
            };
        };
        hasher.update(rel_path);
        hasher.update(&[_]u8{0});
        hasher.update(bytes);
        hasher.update(&[_]u8{0});
    }
}

fn collectZigFilesRecursivelySorted(
    arena: std.mem.Allocator,
    io: std.Io,
    root_dir: []const u8,
) ![]const []const u8 {
    var root = std.Io.Dir.cwd().openDir(io, root_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer root.close(io);

    var walker = try root.walk(arena);
    defer walker.deinit();

    var rel_paths = std.ArrayList([]const u8).empty;
    errdefer rel_paths.deinit(arena);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;

        const rel = try arena.dupe(u8, entry.path);
        for (rel) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
        try rel_paths.append(arena, rel);
    }

    std.mem.sort([]const u8, rel_paths.items, {}, text_utils.lessStringSlice);
    return rel_paths.toOwnedSlice(arena);
}
