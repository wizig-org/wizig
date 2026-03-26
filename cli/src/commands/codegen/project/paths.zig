//! Generated output path discovery and optional SDK mirror targets.

const std = @import("std");
const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");

/// Returns the Swift mirror path for the lexicographically first top-level
/// `.xcodeproj` under `ios/`.
///
/// Multi-project repos can contain several host projects under `ios/`. This
/// resolver ignores nested `.xcodeproj` directories and selects the first
/// top-level match in sorted order so the mirror target is stable across
/// filesystem walk order.
pub fn resolveIosMirrorSwiftFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const ios_dir = try path_util.join(arena, project_root, "ios");
    if (!fs_util.pathExists(io, ios_dir)) return null;

    var ios = std.Io.Dir.cwd().openDir(io, ios_dir, .{ .iterate = true }) catch return null;
    defer ios.close(io);

    var walker = try ios.walk(arena);
    defer walker.deinit();

    var project_paths = std.ArrayList([]const u8).empty;
    defer project_paths.deinit(arena);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.endsWith(u8, entry.path, ".xcodeproj")) continue;
        if (std.mem.indexOfAny(u8, entry.path, "/\\") != null) continue;

        try project_paths.append(arena, try arena.dupe(u8, entry.path));
    }

    std.mem.sort([]const u8, project_paths.items, {}, lessString);

    for (project_paths.items) |project_path| {
        const project_name = std.fs.path.stem(project_path);
        if (project_name.len == 0) continue;
        const host_dir = try path_util.join(arena, ios_dir, project_name);
        if (!fs_util.pathExists(io, host_dir)) continue;

        const generated_dir = try path_util.join(arena, host_dir, "Generated");
        try fs_util.ensureDir(io, generated_dir);
        const mirror_path = try path_util.join(arena, generated_dir, "WizigGeneratedApi.swift");
        return @as(?[]const u8, mirror_path);
    }

    return null;
}

fn lessString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

pub fn resolveSdkSwiftApiFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const sdk_dir = try path_util.join(arena, project_root, ".wizig/sdk/ios/Sources/Wizig");
    if (!fs_util.pathExists(io, sdk_dir)) return null;
    const path = try path_util.join(arena, sdk_dir, "WizigGeneratedApi.swift");
    return @as(?[]const u8, path);
}

pub fn resolveSdkIosRuntimeFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const sdk_dir = try path_util.join(arena, project_root, ".wizig/sdk/ios/Sources/Wizig");
    if (!fs_util.pathExists(io, sdk_dir)) return null;
    const path = try path_util.join(arena, sdk_dir, "WizigRuntime.swift");
    return @as(?[]const u8, path);
}

pub fn resolveBundledIosRuntimeSource(
    arena: std.mem.Allocator,
    io: std.Io,
) !?[]const u8 {
    const exe_path = std.process.executablePathAlloc(io, arena) catch return null;
    const exe_dir = std.fs.path.dirname(exe_path) orelse return null;

    const install_candidate = try std.fs.path.resolve(arena, &.{
        exe_dir,
        "..",
        "share",
        "wizig",
        "sdk",
        "ios",
        "Sources",
        "Wizig",
        "WizigRuntime.swift",
    });
    if (fs_util.pathExists(io, install_candidate)) return install_candidate;

    const dev_candidate = try std.fs.path.resolve(arena, &.{
        exe_dir,
        "..",
        "..",
        "sdk",
        "ios",
        "Sources",
        "Wizig",
        "WizigRuntime.swift",
    });
    if (fs_util.pathExists(io, dev_candidate)) return dev_candidate;

    return null;
}

/// Returns the SDK iOS WizigFFI include directory for C header mirroring.
pub fn resolveSdkIosFfiIncludeDir(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const sdk_dir = try path_util.join(arena, project_root, ".wizig/sdk/ios/Sources/WizigFFI/include");
    if (!fs_util.pathExists(io, sdk_dir)) return null;
    return @as(?[]const u8, sdk_dir);
}

/// Returns the SDK iOS WizigFFI C shim file path when present.
pub fn resolveSdkIosFfiStubSource(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const path = try path_util.join(arena, project_root, ".wizig/sdk/ios/Sources/WizigFFI/stub.c");
    if (!fs_util.pathExists(io, path)) return null;
    return @as(?[]const u8, path);
}

pub fn resolveSdkKotlinApiFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
    const sdk_dir = try path_util.join(arena, project_root, ".wizig/sdk/android/src/main/kotlin/dev/wizig");
    if (!fs_util.pathExists(io, sdk_dir)) return null;
    const path = try path_util.join(arena, sdk_dir, "WizigGeneratedApi.kt");
    return @as(?[]const u8, path);
}

test "resolveIosMirrorSwiftFile selects the first top-level xcodeproj deterministically" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    const project_root = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/sample-app", .{tmp.sub_path});
    const ios_dir = try path_util.join(arena, project_root, "ios");
    try std.Io.Dir.cwd().createDirPath(io, ios_dir);

    const zeta_proj = try path_util.join(arena, ios_dir, "Zeta.xcodeproj");
    const alpha_proj = try path_util.join(arena, ios_dir, "Alpha.xcodeproj");
    const nested_dir = try path_util.join(arena, ios_dir, "Aardvark");
    const nested_proj = try path_util.join(arena, nested_dir, "Nested.xcodeproj");
    try std.Io.Dir.cwd().createDirPath(io, zeta_proj);
    try std.Io.Dir.cwd().createDirPath(io, alpha_proj);
    try std.Io.Dir.cwd().createDirPath(io, nested_proj);

    const zeta_host_dir = try path_util.join(arena, ios_dir, "Zeta");
    const alpha_host_dir = try path_util.join(arena, ios_dir, "Alpha");
    const nested_host_dir = try path_util.join(arena, ios_dir, "Nested");
    try std.Io.Dir.cwd().createDirPath(io, zeta_host_dir);
    try std.Io.Dir.cwd().createDirPath(io, alpha_host_dir);
    try std.Io.Dir.cwd().createDirPath(io, nested_host_dir);

    const resolved = try resolveIosMirrorSwiftFile(arena, io, project_root);
    try std.testing.expect(resolved != null);
    const alpha_generated_dir = try path_util.join(arena, alpha_host_dir, "Generated");
    const alpha_mirror_path = try path_util.join(arena, alpha_generated_dir, "WizigGeneratedApi.swift");
    try std.testing.expectEqualStrings(
        alpha_mirror_path,
        resolved.?,
    );

    const nested_generated_dir = try path_util.join(arena, nested_host_dir, "Generated");
    try std.testing.expect(fs_util.pathExists(io, alpha_generated_dir));
    try std.testing.expect(!fs_util.pathExists(io, nested_generated_dir));
}
