//! Android Gradle file compatibility migrations for host-managed FFI.
//!
//! This entrypoint keeps the public API small and delegates the text rewrite
//! rules to `android_gradle_migration/patch.zig`.
const std = @import("std");

const fs_utils = @import("fs_utils.zig");
const patch = @import("android_gradle_migration/patch.zig");

/// Result metadata describing whether Android Gradle migration touched the file.
pub const MigrationSummary = struct {
    /// True when `<module>/build.gradle.kts` existed and was inspected.
    inspected: bool = false,
    /// True when compatibility rewrites were applied and persisted.
    patched: bool = false,
};

/// Ensures Android host build file compatibility for current Gradle APIs.
///
/// This function is intentionally cheap (`read -> patch -> compare -> write`),
/// so it can be called on every Android run invocation without measurable
/// overhead.
pub fn ensureBuildGradleKtsCompatibility(
    arena: std.mem.Allocator,
    io: std.Io,
    project_dir: []const u8,
    module: []const u8,
) !MigrationSummary {
    const module_dir = try fs_utils.joinPath(arena, project_dir, module);
    const build_gradle_kts = try fs_utils.joinPath(arena, module_dir, "build.gradle.kts");
    if (!fs_utils.pathExists(io, build_gradle_kts)) return .{};

    const original = try std.Io.Dir.cwd().readFileAlloc(io, build_gradle_kts, arena, .limited(4 * 1024 * 1024));
    const patched = try patch.patchBuildGradleKtsText(arena, original);
    if (std.mem.eql(u8, original, patched)) {
        return .{ .inspected = true, .patched = false };
    }

    try fs_utils.writeFileAtomically(io, build_gradle_kts, patched);
    return .{ .inspected = true, .patched = true };
}

test {
    _ = @import("android_gradle_migration/tests.zig");
}
