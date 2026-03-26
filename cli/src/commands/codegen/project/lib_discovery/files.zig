//! Filesystem discovery helpers for `lib/**/*.zig`.
const std = @import("std");

const fs_util = @import("../../../../support/fs.zig");
const path_util = @import("../../../../support/path.zig");

/// Discovers normalized `lib/**/*.zig` file paths in deterministic order.
pub fn discoverLibSourcePaths(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
    const lib_dir = try resolveLibDir(arena, project_root);
    if (!fs_util.pathExists(io, lib_dir)) return &.{};

    var lib = std.Io.Dir.cwd().openDir(io, lib_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer lib.close(io);

    return walkLibSources(arena, io, lib);
}

/// Collects import paths for `lib/**/*.zig` files.
pub fn collectLibModuleImports(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
    return discoverLibSourcePaths(arena, io, project_root);
}

fn resolveLibDir(
    arena: std.mem.Allocator,
    project_root: []const u8,
) ![]const u8 {
    return path_util.join(arena, project_root, "lib");
}

fn walkLibSources(
    arena: std.mem.Allocator,
    io: std.Io,
    lib_dir: std.Io.Dir,
) ![]const []const u8 {
    var walker = try lib_dir.walk(arena);
    defer walker.deinit();

    var rel_paths = std.ArrayList([]const u8).empty;
    errdefer rel_paths.deinit(arena);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!isDiscoverableLibSource(entry.path)) continue;
        try rel_paths.append(arena, try normalizeWalkPath(arena, entry.path));
    }

    std.mem.sort([]const u8, rel_paths.items, {}, lessString);
    return rel_paths.toOwnedSlice(arena);
}

fn isDiscoverableLibSource(entry_path: []const u8) bool {
    return std.mem.endsWith(u8, entry_path, ".zig") and
        !std.mem.eql(u8, entry_path, "WizigGeneratedAppModule.zig");
}

fn normalizeWalkPath(arena: std.mem.Allocator, entry_path: []const u8) ![]const u8 {
    const normalized = try arena.dupe(u8, entry_path);
    for (normalized) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
    return normalized;
}

fn lessString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

test "normalizeWalkPath converts separators" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const normalized = try normalizeWalkPath(arena, "nested\\file.zig");
    try std.testing.expectEqualStrings("nested/file.zig", normalized);
}

test "discoverLibSourcePaths sorts results and skips generated module" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    const project_root = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/sample-app", .{tmp.sub_path});
    const lib_dir = try resolveLibDir(arena, project_root);
    const nested_dir = try path_util.join(arena, lib_dir, "nested");
    try std.Io.Dir.cwd().createDirPath(io, nested_dir);

    try fs_util.writeFileAtomically(io, try path_util.join(arena, lib_dir, "b.zig"), "pub fn b() void {}\n");
    try fs_util.writeFileAtomically(io, try path_util.join(arena, nested_dir, "a.zig"), "pub fn a() void {}\n");
    try fs_util.writeFileAtomically(io, try path_util.join(arena, lib_dir, "WizigGeneratedAppModule.zig"), "pub fn generated() void {}\n");

    const sources = try discoverLibSourcePaths(arena, io, project_root);
    try std.testing.expectEqual(@as(usize, 2), sources.len);
    try std.testing.expectEqualStrings("b.zig", sources[0]);
    try std.testing.expectEqualStrings("nested/a.zig", sources[1]);
}
