//! Android host scaffold generation.
//!
//! This module renders the Android template tree, normalizes package-related
//! identifiers, and writes local SDK hints used by Gradle.
const std = @import("std");
const Io = std.Io;

const fs_util = @import("../../support/fs.zig");
const scaffold_strings = @import("scaffold_strings.zig");
const scaffold_template_tree = @import("scaffold_template_tree.zig");
const scaffold_util = @import("scaffold_util.zig");

/// Creates the Android host scaffold and initializes local build metadata.
///
/// When Android SDK paths are available in the environment this function writes
/// `local.properties` to make `./gradlew` usable immediately.
pub fn createAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    templates_root: []const u8,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
    force_host_overwrite: bool,
) !void {
    const app_name = try scaffold_strings.sanitizeProjectName(arena, app_name_raw);
    const app_type_name = try scaffold_strings.toSwiftTypeName(arena, app_name);
    const app_identifier = try scaffold_strings.toIdentifierLower(arena, app_name);
    const destination_dir = destination_dir_raw;
    const package_segment = try scaffold_strings.sanitizePackageSegment(arena, app_name);
    const package_name = try std.fmt.allocPrint(arena, "dev.wizig.{s}", .{package_segment});
    const package_path = try scaffold_strings.packageNameToPath(arena, package_name);
    const package_path_forward = try scaffold_strings.toForwardSlashes(arena, package_path);

    std.Io.Dir.cwd().createDirPath(io, destination_dir) catch |err| {
        try stderr.print("error: failed to create destination '{s}': {s}\n", .{ destination_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const tokens = [_]fs_util.RenderToken{
        .{ .key = "APP_NAME", .value = app_name },
        .{ .key = "APP_IDENTIFIER", .value = app_identifier },
        .{ .key = "APP_TYPE_NAME", .value = app_type_name },
        .{ .key = "ANDROID_PACKAGE", .value = package_name },
    };
    const path_tokens = [_]scaffold_template_tree.PathToken{
        .{ .key = "__ANDROID_PACKAGE_PATH__", .value = package_path_forward },
    };

    const template_dir = try scaffold_util.joinPath(arena, templates_root, "app/android");
    scaffold_template_tree.copyTemplateTreeRendered(
        arena,
        io,
        template_dir,
        destination_dir,
        &tokens,
        &path_tokens,
        force_host_overwrite,
    ) catch |err| {
        try stderr.print("error: failed to scaffold Android host from templates: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    const sdk_dir = parent_environ_map.get("ANDROID_SDK_ROOT") orelse parent_environ_map.get("ANDROID_HOME");
    if (sdk_dir != null and (force_host_overwrite or !fs_util.pathExists(io, try scaffold_util.joinPath(arena, destination_dir, "local.properties")))) {
        const local_properties_path = try scaffold_util.joinPath(arena, destination_dir, "local.properties");
        const escaped_sdk = try scaffold_strings.escapeLocalPropertiesValue(arena, sdk_dir.?);
        const local_properties_contents = try std.fmt.allocPrint(arena, "sdk.dir={s}\n", .{escaped_sdk});
        try scaffold_util.writeFileAtomically(io, local_properties_path, local_properties_contents);
    }

    const gradlew_path = try scaffold_util.joinPath(arena, destination_dir, "gradlew");
    if (fs_util.pathExists(io, gradlew_path)) {
        scaffold_util.runCommand(arena, io, stderr, ".", &.{ "chmod", "+x", gradlew_path }, null) catch {};
    }

    try stdout.print("created Android app '{s}' at '{s}'\n", .{ app_name, destination_dir });
    try stdout.print("next: (cd {s} && ./gradlew :app:assembleDebug)\n", .{destination_dir});
    try stdout.flush();
}
