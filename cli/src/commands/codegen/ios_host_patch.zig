//! iOS host project patching for direct Xcode FFI builds.
//!
//! Direct Xcode builds do not run `wizig run`, so codegen keeps generated host
//! projects wired to the current FFI packaging flow by patching the project
//! file deterministically and idempotently.
const std = @import("std");

const fs_util = @import("../../support/fs.zig");
const path_util = @import("../../support/path.zig");
const project_patcher = @import("ios_host_patch/project_patcher.zig");

/// Summary of iOS host project patching work performed in one codegen pass.
pub const PatchSummary = struct {
    /// Number of discovered `.xcodeproj` files scanned for migration.
    scanned_projects: usize = 0,
    /// Number of project files updated with new build phase wiring.
    patched_projects: usize = 0,
};

/// Ensures all discovered iOS host projects include Wizig's FFI build phase.
pub fn ensureIosHostBuildPhase(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !PatchSummary {
    const ios_dir = try path_util.join(arena, project_root, "ios");
    if (!fs_util.pathExists(io, ios_dir)) return .{};

    var result: PatchSummary = .{};
    var ios = std.Io.Dir.cwd().openDir(io, ios_dir, .{ .iterate = true }) catch return result;
    defer ios.close(io);

    var walker = try ios.walk(arena);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .directory or !std.mem.endsWith(u8, entry.path, ".xcodeproj")) continue;

        result.scanned_projects += 1;
        const pbx_path = try std.fmt.allocPrint(arena, "{s}{s}{s}{s}project.pbxproj", .{
            ios_dir,
            std.fs.path.sep_str,
            entry.path,
            std.fs.path.sep_str,
        });
        if (!fs_util.pathExists(io, pbx_path)) continue;

        if (try project_patcher.patchProjectFile(arena, io, pbx_path)) {
            result.patched_projects += 1;
        }
    }

    return result;
}

test {
    _ = @import("ios_host_patch/tests_patching.zig");
    _ = @import("ios_host_patch/tests_signing.zig");
    _ = @import("ios_host_patch/tests_phase_entry.zig");
}
