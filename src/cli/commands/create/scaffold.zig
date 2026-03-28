//! Project scaffolding orchestrator for `wizig create`.
//!
//! This file coordinates high-level creation flow. Platform-specific host
//! generation and low-level utilities live in separate modules to keep each
//! implementation unit focused and below the line-limit policy.
const std = @import("std");
const Io = std.Io;

const fs_util = @import("../../support/fs.zig");
const sdk_locator = @import("../../support/sdk_locator.zig");
const codegen_cmd = @import("../codegen/root.zig");
const toolchain_lock = @import("toolchain_lock.zig");
const scaffold_strings = @import("scaffold_strings.zig");
const scaffold_util = @import("scaffold_util.zig");
const ios_scaffold = @import("ios_scaffold.zig");
const android_scaffold = @import("android_scaffold.zig");

/// Errors emitted by scaffolding helpers.
pub const CreateError = error{CreateFailed};

/// Platform selection for generated hosts.
///
/// - `ios`: Generate an iOS host project from templates.
/// - `android`: Generate an Android host project from templates.
/// - `macos`: Reserve a placeholder host directory for future desktop support.
pub const CreatePlatforms = struct {
    ios: bool = true,
    android: bool = true,
    macos: bool = false,
};

/// Creates a full Wizig application scaffold at `destination_dir_raw`.
///
/// The workflow materializes SDK/runtime files, generates selected host
/// projects, runs initial codegen, and records toolchain lock metadata.
pub fn createApp(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
    platforms: CreatePlatforms,
    explicit_sdk_root: ?[]const u8,
    force_host_overwrite: bool,
) !void {
    if (!hasAnyPlatform(platforms)) {
        try stderr.writeAll("error: at least one platform must be selected\n");
        try stderr.flush();
        return error.CreateFailed;
    }

    const app_name = try scaffold_strings.sanitizeProjectName(arena, app_name_raw);
    const app_identifier = try scaffold_strings.toIdentifierLower(arena, app_name);
    const destination_dir = destination_dir_raw;

    std.Io.Dir.cwd().createDirPath(io, destination_dir) catch |err| {
        try stderr.print("error: failed to create destination '{s}': {s}\n", .{ destination_dir, @errorName(err) });
        try stderr.flush();
        return error.CreateFailed;
    };

    const resolved = sdk_locator.resolve(arena, io, parent_environ_map, stderr, explicit_sdk_root) catch {
        try stderr.flush();
        return error.CreateFailed;
    };

    const dot_wizig_dir = try scaffold_util.joinPath(arena, destination_dir, ".wizig");
    const lib_dir = try scaffold_util.joinPath(arena, destination_dir, "lib");
    const plugins_dir = try scaffold_util.joinPath(arena, destination_dir, "plugins");
    const app_sdk_dir = try scaffold_util.joinPath(arena, dot_wizig_dir, "sdk");
    const app_runtime_dir = try scaffold_util.joinPath(arena, dot_wizig_dir, "runtime");
    const app_generated_dir = try scaffold_util.joinPath(arena, dot_wizig_dir, "generated");
    const app_generated_swift_dir = try scaffold_util.joinPath(arena, app_generated_dir, "swift");
    const app_generated_kotlin_dir = try scaffold_util.joinPath(arena, app_generated_dir, "kotlin");
    const app_generated_zig_dir = try scaffold_util.joinPath(arena, app_generated_dir, "zig");
    const app_generated_android_dir = try scaffold_util.joinPath(arena, app_generated_dir, "android");
    const app_generated_android_jnilibs_dir = try scaffold_util.joinPath(arena, app_generated_android_dir, "jniLibs");
    const app_plugins_meta_dir = try scaffold_util.joinPath(arena, dot_wizig_dir, "plugins");

    for (&[_][]const u8{
        lib_dir,
        plugins_dir,
        app_sdk_dir,
        app_runtime_dir,
        app_generated_dir,
        app_generated_swift_dir,
        app_generated_kotlin_dir,
        app_generated_zig_dir,
        app_generated_android_dir,
        app_generated_android_jnilibs_dir,
        app_plugins_meta_dir,
    }) |dir_path| {
        std.Io.Dir.cwd().createDirPath(io, dir_path) catch |err| {
            try stderr.print("error: failed to create '{s}': {s}\n", .{ dir_path, @errorName(err) });
            try stderr.flush();
            return error.CreateFailed;
        };
    }
    try scaffold_util.writeFileAtomically(io, try scaffold_util.joinPath(arena, app_generated_android_jnilibs_dir, ".gitkeep"), "");

    fs_util.removeTreeIfExists(io, app_sdk_dir) catch {};
    fs_util.removeTreeIfExists(io, app_runtime_dir) catch {};

    fs_util.copyTree(arena, io, resolved.sdk_dir, app_sdk_dir) catch |err| {
        try stderr.print("error: failed to copy SDK into app (.wizig/sdk): {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };
    fs_util.copyTree(arena, io, resolved.runtime_dir, app_runtime_dir) catch |err| {
        try stderr.print("error: failed to copy runtime into app (.wizig/runtime): {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    const template_tokens = [_]fs_util.RenderToken{
        .{ .key = "APP_NAME", .value = app_name },
        .{ .key = "APP_IDENTIFIER", .value = app_identifier },
        .{ .key = "APP_TYPE_NAME", .value = try scaffold_strings.toSwiftTypeName(arena, app_name) },
    };

    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/.gitignore", try scaffold_util.joinPath(arena, destination_dir, ".gitignore"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/README.md", try scaffold_util.joinPath(arena, destination_dir, "README.md"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/wizig.yaml", try scaffold_util.joinPath(arena, destination_dir, "wizig.yaml"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/lib/main.zig", try scaffold_util.joinPath(arena, lib_dir, "main.zig"), &template_tokens);
    try renderTemplateToPath(arena, io, resolved.templates_dir, "app/plugins/README.md", try scaffold_util.joinPath(arena, plugins_dir, "README.md"), &template_tokens);

    if (platforms.ios) {
        const ios_dir = try scaffold_util.joinPath(arena, destination_dir, "ios");
        ios_scaffold.createIos(arena, io, stderr, stdout, resolved.templates_dir, app_name, ios_dir, force_host_overwrite) catch return error.CreateFailed;
    }
    if (platforms.android) {
        const android_dir = try scaffold_util.joinPath(arena, destination_dir, "android");
        android_scaffold.createAndroid(
            arena,
            io,
            parent_environ_map,
            stderr,
            stdout,
            resolved.templates_dir,
            app_name,
            android_dir,
            force_host_overwrite,
        ) catch return error.CreateFailed;
    }
    if (platforms.macos) {
        const macos_dir = try scaffold_util.joinPath(arena, destination_dir, "macos");
        std.Io.Dir.cwd().createDirPath(io, macos_dir) catch |err| {
            try stderr.print("error: failed to create macOS dir '{s}': {s}\n", .{ macos_dir, @errorName(err) });
            try stderr.flush();
            return error.CreateFailed;
        };
        const macos_readme_path = try scaffold_util.joinPath(arena, macos_dir, "README.md");
        try scaffold_util.writeFileAtomically(
            io,
            macos_readme_path,
            "# macOS (placeholder)\n\nDesktop scaffolding will be added in a future Wizig release.\n",
        );
    }

    codegen_cmd.generateProject(arena, io, stderr, stdout, destination_dir, null) catch |err| {
        try stderr.print("error: failed to run initial codegen: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return error.CreateFailed;
    };

    toolchain_lock.writeProjectLock(
        arena,
        io,
        stderr,
        stdout,
        resolved.root,
        destination_dir,
    ) catch return error.CreateFailed;

    try stdout.print("created Wizig app '{s}' at '{s}'\n", .{ app_name, destination_dir });
    try stdout.flush();
}

fn renderTemplateToPath(
    arena: std.mem.Allocator,
    io: std.Io,
    templates_root: []const u8,
    template_rel: []const u8,
    output_path: []const u8,
    tokens: []const fs_util.RenderToken,
) !void {
    const template = try fs_util.readTemplate(arena, io, templates_root, template_rel);
    const rendered = try fs_util.renderTemplate(arena, template, tokens);
    try fs_util.writeFileAtomically(io, output_path, rendered);
}

fn hasAnyPlatform(platforms: CreatePlatforms) bool {
    return platforms.ios or platforms.android or platforms.macos;
}
