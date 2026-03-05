//! Android release build pipeline for Play Store distribution.
//!
//! Builds FFI for each target ABI using Zig cross-compilation with release
//! optimizations, then runs Gradle `bundleRelease` to produce an AAB.

const std = @import("std");
const Io = std.Io;

const android_multi_abi = @import("android_multi_abi.zig");

/// Executes a full Android release build.
///
/// Steps:
/// 1. Resolve FFI build inputs from workspace/runtime
/// 2. Build FFI shared libraries for each target ABI
/// 3. Run Gradle `bundleRelease` to produce an AAB
pub fn runAndroidReleaseBuild(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    abis: []const []const u8,
) !void {
    // Resolve FFI root source from the generated output
    const ffi_root = try std.fmt.allocPrint(arena, "{s}/.wizig/generated/zig/WizigGeneratedFfiRoot.zig", .{project_root});
    const core_source = try std.fmt.allocPrint(arena, "{s}/.wizig/runtime/core/src/root.zig", .{project_root});
    const app_source_path = try std.fmt.allocPrint(arena, "{s}/lib/WizigGeneratedAppModule.zig", .{project_root});

    const app_source: ?[]const u8 = blk: {
        _ = std.Io.Dir.cwd().statFile(io, app_source_path, .{}) catch break :blk null;
        break :blk app_source_path;
    };

    try stdout.writeAll("building multi-ABI release FFI libraries...\n");
    try stdout.flush();

    const build_result = try android_multi_abi.buildMultiAbiFfi(
        arena,
        io,
        stderr,
        stdout,
        project_root,
        ffi_root,
        core_source,
        app_source,
        abis,
        true, // release
    );

    try stdout.print("built FFI for {d} ABIs: ", .{build_result.built_abis.len});
    for (build_result.built_abis, 0..) |abi, i| {
        if (i > 0) try stdout.writeAll(", ");
        try stdout.writeAll(abi);
    }
    try stdout.writeAll("\n");
    try stdout.flush();

    // Run Gradle bundleRelease
    const android_dir = try std.fmt.allocPrint(arena, "{s}/android", .{project_root});

    // Use gradlew if present, otherwise fall back to gradle
    const gradlew_path = try std.fmt.allocPrint(arena, "{s}/gradlew", .{android_dir});
    const gradle_cmd: []const u8 = blk: {
        _ = std.Io.Dir.cwd().statFile(io, gradlew_path, .{}) catch break :blk "gradle";
        break :blk gradlew_path;
    };

    try stdout.writeAll("running Gradle bundleRelease...\n");
    try stdout.flush();

    const result = std.process.run(arena, io, .{
        .argv = &.{ gradle_cmd, ":app:bundleRelease" },
        .cwd = .{ .path = android_dir },
    }) catch |err| {
        try stderr.print("error: failed to run Gradle bundleRelease: {s}\n", .{@errorName(err)});
        return error.BuildFailed;
    };

    if (!termIsSuccess(result.term)) {
        try stderr.writeAll("error: Gradle bundleRelease failed\n");
        if (result.stderr.len > 0) {
            try stderr.writeAll(result.stderr);
        }
        return error.BuildFailed;
    }

    try stdout.writeAll("Android release build complete.\n");
    try stdout.flush();
}

/// Default Play Store ABIs for release builds.
pub const release_abis: []const []const u8 = &.{ "arm64-v8a", "armeabi-v7a", "x86_64" };

fn termIsSuccess(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

test "release ABIs match Play Store target set" {
    try std.testing.expectEqual(3, release_abis.len);
    try std.testing.expectEqualStrings("arm64-v8a", release_abis[0]);
    try std.testing.expectEqualStrings("armeabi-v7a", release_abis[1]);
    try std.testing.expectEqualStrings("x86_64", release_abis[2]);
}
