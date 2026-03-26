//! Plugin registry synchronization for `wizig plugin sync`.
const std = @import("std");
const Io = std.Io;

const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");
const managed_sections = @import("managed_sections.zig");
const wizig_core = @import("wizig_core");

/// Scans plugin manifests, writes generated registrants, and refreshes managed blocks.
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root_raw: []const u8,
) !void {
    const project_root = try path_util.resolveAbsolute(arena, io, project_root_raw);
    const plugin_root = try path_util.join(arena, project_root, "plugins");
    const registry_dir = try path_util.join(arena, project_root, ".wizig/plugins");
    const generated_dir = try path_util.join(arena, project_root, ".wizig/generated");
    const swift_dir = try path_util.join(arena, generated_dir, "swift");
    const kotlin_dir = try path_util.join(arena, generated_dir, "kotlin/dev/wizig");
    const zig_dir = try path_util.join(arena, generated_dir, "zig");

    for (&[_][]const u8{ registry_dir, swift_dir, kotlin_dir, zig_dir }) |dir_path| {
        try fs_util.ensureDir(io, dir_path);
    }

    var registry = wizig_core.collectPluginRegistry(arena, io, plugin_root) catch |err| {
        try stderr.print("error: failed to collect plugins from '{s}': {s}\n", .{ plugin_root, @errorName(err) });
        return error.PluginFailed;
    };
    defer registry.deinit(arena);

    const lockfile = wizig_core.renderPluginLockfile(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render lockfile: {s}\n", .{@errorName(err)});
        return error.PluginFailed;
    };
    const zig_registrant = wizig_core.renderZigRegistrant(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render Zig registrant: {s}\n", .{@errorName(err)});
        return error.PluginFailed;
    };
    const swift_registrant = wizig_core.renderSwiftRegistrant(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render Swift registrant: {s}\n", .{@errorName(err)});
        return error.PluginFailed;
    };
    const kotlin_registrant = wizig_core.renderKotlinRegistrant(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render Kotlin registrant: {s}\n", .{@errorName(err)});
        return error.PluginFailed;
    };

    const lockfile_path = try path_util.join(arena, registry_dir, "plugins.lock.toml");
    const zig_path = try path_util.join(arena, zig_dir, "generated_plugins.zig");
    const swift_path = try path_util.join(arena, swift_dir, "GeneratedPluginRegistrant.swift");
    const kotlin_path = try path_util.join(arena, kotlin_dir, "GeneratedPluginRegistrant.kt");
    const sdk_swift_path = try path_util.join(arena, project_root, ".wizig/sdk/ios/Sources/Wizig/GeneratedPluginRegistrant.swift");
    const sdk_kotlin_path = try path_util.join(arena, project_root, ".wizig/sdk/android/src/main/kotlin/dev/wizig/GeneratedPluginRegistrant.kt");
    const sdk_ios_sources = try path_util.join(arena, project_root, ".wizig/sdk/ios/Sources/Wizig");
    const sdk_android_sources = try path_util.join(arena, project_root, ".wizig/sdk/android/src/main/kotlin/dev/wizig");

    try fs_util.writeFileAtomically(io, lockfile_path, lockfile);
    try fs_util.writeFileAtomically(io, zig_path, zig_registrant);
    try fs_util.writeFileAtomically(io, swift_path, swift_registrant);
    try fs_util.writeFileAtomically(io, kotlin_path, kotlin_registrant);
    if (fs_util.pathExists(io, sdk_ios_sources)) {
        try fs_util.writeFileAtomically(io, sdk_swift_path, swift_registrant);
    }
    if (fs_util.pathExists(io, sdk_android_sources)) {
        try fs_util.writeFileAtomically(io, sdk_kotlin_path, kotlin_registrant);
    }

    try managed_sections.updateManagedPluginSections(arena, io, project_root, registry.records);

    try stdout.print(
        "generated {d} plugins\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n",
        .{ registry.records.len, lockfile_path, zig_path, swift_path, kotlin_path, sdk_swift_path, sdk_kotlin_path },
    );
    try stdout.flush();
}
