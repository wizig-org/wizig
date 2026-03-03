//! Generated output path discovery and optional SDK mirror targets.

const std = @import("std");
const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");

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

    while (try walker.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.endsWith(u8, entry.path, ".xcodeproj")) continue;

        const project_name = std.fs.path.stem(entry.path);
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
