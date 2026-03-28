//! Incremental fingerprinting for codegen watch mode.
//!
//! ## Purpose
//! Watch mode needs a cheap signal for "inputs changed". This module computes a
//! deterministic SHA-256 fingerprint using file metadata (path, size, mtime)
//! rather than re-reading every file on every poll.
//!
//! ## Tracked Inputs
//! - `lib/**/*.zig` (excluding `lib/WizigGeneratedAppModule.zig`)
//! - contract selection and contract metadata (`wizig.api.zig` / `.json` / `--api`)
//! - presence of required generated outputs (to recover from deleted artifacts)
//!
//! ## Performance Characteristics
//! - O(number of Zig source files) stat calls per poll.
//! - No large file reads, minimizing overhead during active editing.
const std = @import("std");
const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");

const watch_fingerprint_version = "wizig-codegen-watch-v1";

const WatchLibEntry = struct {
    rel_path: []const u8,
    size: u64,
    mtime_ns: i96,
};

/// Computes the current watch fingerprint for a codegen project.
///
/// Parameters:
/// - `project_root`: Absolute project root path.
/// - `api_path`: Resolved contract path when available, otherwise `null`.
pub fn computeWatchFingerprint(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    api_path: ?[]const u8,
) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(watch_fingerprint_version);
    hasher.update(&[_]u8{0});
    hasher.update(project_root);
    hasher.update(&[_]u8{0});

    try hashContractState(arena, io, project_root, api_path, &hasher);
    try hashLibTreeState(arena, io, project_root, &hasher);
    try hashGeneratedOutputsState(arena, io, project_root, &hasher);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

/// Hashes contract presence/metadata into the watch fingerprint.
fn hashContractState(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    api_path: ?[]const u8,
    hasher: *std.crypto.hash.sha2.Sha256,
) !void {
    if (api_path) |path| {
        hasher.update("contract");
        hasher.update(&[_]u8{0});
        hasher.update(path);
        hasher.update(&[_]u8{0});
        const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                hasher.update("missing");
                hasher.update(&[_]u8{0});
                return;
            },
            else => return err,
        };
        hashFileMetadata(hasher, stat.size, stat.mtime.toNanoseconds());
        return;
    }

    const default_zig = try path_util.join(arena, project_root, "wizig.api.zig");
    const default_json = try path_util.join(arena, project_root, "wizig.api.json");
    hasher.update("contract:auto");
    hasher.update(&[_]u8{0});
    hasher.update(if (fs_util.pathExists(io, default_zig)) "zig:1" else "zig:0");
    hasher.update(&[_]u8{0});
    hasher.update(if (fs_util.pathExists(io, default_json)) "json:1" else "json:0");
    hasher.update(&[_]u8{0});
}

/// Hashes `lib/**/*.zig` metadata into the watch fingerprint.
fn hashLibTreeState(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    hasher: *std.crypto.hash.sha2.Sha256,
) !void {
    const lib_root = try path_util.join(arena, project_root, "lib");
    if (!fs_util.pathExists(io, lib_root)) {
        hasher.update("lib:missing");
        hasher.update(&[_]u8{0});
        return;
    }

    var lib_dir = std.Io.Dir.cwd().openDir(io, lib_root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            hasher.update("lib:missing");
            hasher.update(&[_]u8{0});
            return;
        },
        else => return err,
    };
    defer lib_dir.close(io);

    var walker = try lib_dir.walk(arena);
    defer walker.deinit();

    var entries = std.ArrayList(WatchLibEntry).empty;
    defer entries.deinit(arena);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".zig")) continue;
        if (std.mem.eql(u8, entry.path, "WizigGeneratedAppModule.zig")) continue;

        const rel = try arena.dupe(u8, entry.path);
        for (rel) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }

        const stat = lib_dir.statFile(io, entry.path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        try entries.append(arena, .{
            .rel_path = rel,
            .size = stat.size,
            .mtime_ns = stat.mtime.toNanoseconds(),
        });
    }

    std.mem.sort(WatchLibEntry, entries.items, {}, lessWatchLibEntry);
    for (entries.items) |item| {
        hasher.update(item.rel_path);
        hasher.update(&[_]u8{0});
        hashFileMetadata(hasher, item.size, item.mtime_ns);
    }
}

/// Hashes required generated-output presence into the fingerprint.
fn hashGeneratedOutputsState(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    hasher: *std.crypto.hash.sha2.Sha256,
) !void {
    const required_outputs = [_][]const u8{
        ".wizig/generated/zig/WizigGeneratedApi.zig",
        ".wizig/generated/zig/WizigGeneratedFfiRoot.zig",
        "lib/WizigGeneratedAppModule.zig",
        ".wizig/generated/swift/WizigGeneratedApi.swift",
        ".wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt",
        ".wizig/generated/android/jni/WizigGeneratedApiBridge.c",
        ".wizig/generated/android/jni/CMakeLists.txt",
    };

    for (required_outputs) |rel| {
        const abs = try path_util.join(arena, project_root, rel);
        hasher.update(rel);
        hasher.update(&[_]u8{0});
        hasher.update(if (fs_util.pathExists(io, abs)) "1" else "0");
        hasher.update(&[_]u8{0});
    }
}

/// Appends normalized size+mtime metadata into the hash stream.
fn hashFileMetadata(hasher: *std.crypto.hash.sha2.Sha256, size: u64, mtime_ns: i96) void {
    var metadata_buf: [96]u8 = undefined;
    const metadata = std.fmt.bufPrint(&metadata_buf, "{d}:{d}", .{ size, mtime_ns }) catch unreachable;
    hasher.update(metadata);
    hasher.update(&[_]u8{0});
}

fn lessWatchLibEntry(_: void, lhs: WatchLibEntry, rhs: WatchLibEntry) bool {
    return std.mem.lessThan(u8, lhs.rel_path, rhs.rel_path);
}

test "computeWatchFingerprint changes when lib source changes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    const root = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/watch-app", .{tmp.sub_path});
    const lib_dir = try path_util.join(arena, root, "lib");
    const main_path = try path_util.join(arena, lib_dir, "main.zig");
    try std.Io.Dir.cwd().createDirPath(io, lib_dir);
    try fs_util.writeFileAtomically(io, main_path, "pub fn answer() i64 { return 41; }\n");

    const first = try computeWatchFingerprint(arena, io, root, null);
    try fs_util.writeFileAtomically(io, main_path, "pub fn answer() i64 { return 42; }\n");
    const second = try computeWatchFingerprint(arena, io, root, null);

    try std.testing.expect(!std.mem.eql(u8, &first, &second));
}
