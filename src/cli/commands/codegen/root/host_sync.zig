//! Host-project patching and SDK mirror synchronization after generation.
const std = @import("std");
const Io = std.Io;

const android_gradle_migration = @import("../../../run/platform/android_gradle_migration.zig");
const fs_util = @import("../../../support/fs.zig");
const ios_host_patch = @import("../ios_host_patch.zig");
const path_util = @import("../../../support/path.zig");
const project_ios_sdk_ffi_mirror = @import("../project/ios_sdk_ffi_mirror.zig");
const api = @import("../model/api.zig");

/// Post-generation sync results for patched host projects.
pub const SyncResult = struct {
    ios_host_patch_summary: ios_host_patch.PatchSummary = .{},
    android_host_patch_summary: android_gradle_migration.MigrationSummary = .{},
};

/// Mirrors generated host support artifacts and patches host projects when needed.
pub fn syncHosts(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    spec: api.ApiSpec,
) !SyncResult {
    try project_ios_sdk_ffi_mirror.mirrorGeneratedIosFfiArtifacts(arena, io, project_root, spec);

    const ios_host_patch_summary = ios_host_patch.ensureIosHostBuildPhase(arena, io, project_root) catch |err| blk: {
        try stderr.print("warning: failed to patch iOS host project for Wizig FFI build phase: {s}\n", .{@errorName(err)});
        break :blk ios_host_patch.PatchSummary{};
    };

    const android_project_root = try path_util.join(arena, project_root, "android");
    const android_host_patch_summary = if (fs_util.pathExists(io, android_project_root))
        android_gradle_migration.ensureBuildGradleKtsCompatibility(
            arena,
            io,
            android_project_root,
            "app",
        ) catch |err| blk: {
            try stderr.print("warning: failed to patch Android host Gradle for Wizig FFI build tasks: {s}\n", .{@errorName(err)});
            break :blk android_gradle_migration.MigrationSummary{};
        }
    else
        android_gradle_migration.MigrationSummary{};

    return .{
        .ios_host_patch_summary = ios_host_patch_summary,
        .android_host_patch_summary = android_host_patch_summary,
    };
}
