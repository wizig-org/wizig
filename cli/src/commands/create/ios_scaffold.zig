//! iOS host scaffold generation.
//!
//! This module materializes the iOS template tree and performs token/path
//! substitution for app naming while preserving deterministic seed layout.
const std = @import("std");
const Io = std.Io;

const fs_util = @import("../../support/fs.zig");
const scaffold_strings = @import("scaffold_strings.zig");
const scaffold_template_tree = @import("scaffold_template_tree.zig");
const scaffold_util = @import("scaffold_util.zig");

/// Creates the iOS host scaffold from bundled templates.
///
/// The generated project is immediately buildable using `xcodebuild` and uses
/// a path-token rewrite for seed placeholders such as `__APP_NAME__`.
pub fn createIos(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    templates_root: []const u8,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
    force_host_overwrite: bool,
) !void {
    const app_name = try scaffold_strings.sanitizeProjectName(arena, app_name_raw);
    const destination_dir = destination_dir_raw;

    std.Io.Dir.cwd().createDirPath(io, destination_dir) catch |err| {
        try stderr.print("error: failed to create destination '{s}': {s}\n", .{ destination_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const tokens = [_]fs_util.RenderToken{
        .{ .key = "APP_NAME", .value = app_name },
        .{ .key = "APP_IDENTIFIER", .value = try scaffold_strings.toIdentifierLower(arena, app_name) },
        .{ .key = "APP_TYPE_NAME", .value = try scaffold_strings.toSwiftTypeName(arena, app_name) },
        .{ .key = "ANDROID_PACKAGE", .value = "" },
    };

    const template_dir = try scaffold_util.joinPath(arena, templates_root, "app/ios");
    const path_tokens = [_]scaffold_template_tree.PathToken{
        .{ .key = "__APP_NAME__", .value = app_name },
    };
    scaffold_template_tree.copyTemplateTreeRendered(
        arena,
        io,
        template_dir,
        destination_dir,
        &tokens,
        &path_tokens,
        force_host_overwrite,
    ) catch |err| {
        try stderr.print("error: failed to scaffold iOS host from templates: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    try stdout.print("created iOS app '{s}' at '{s}'\n", .{ app_name, destination_dir });
    try stdout.print(
        "next: xcodebuild -project {s}/{s}.xcodeproj -scheme {s} -destination 'generic/platform=iOS Simulator' build\n",
        .{ destination_dir, app_name, app_name },
    );
    try stdout.flush();
}
