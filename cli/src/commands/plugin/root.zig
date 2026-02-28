const std = @import("std");
const Io = std.Io;
const ziggy_core = @import("ziggy_core");
const fs_util = @import("../../support/fs.zig");
const path_util = @import("../../support/path.zig");
const process_util = @import("../../support/process.zig");

pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
    if (args.len == 0) {
        try stderr.writeAll("error: plugin expects validate|sync|add\n");
        return error.InvalidArguments;
    }

    if (std.mem.eql(u8, args[0], "validate")) {
        if (args.len != 2) {
            try stderr.writeAll("error: plugin validate expects <ziggy-plugin.json>\n");
            return error.InvalidArguments;
        }
        return validate(arena, io, stderr, stdout, args[1]);
    }

    if (std.mem.eql(u8, args[0], "sync")) {
        const project_root = if (args.len >= 2) args[1] else ".";
        if (args.len > 2) {
            try stderr.writeAll("error: plugin sync accepts at most [project_root]\n");
            return error.InvalidArguments;
        }
        return sync(arena, io, stderr, stdout, project_root);
    }

    if (std.mem.eql(u8, args[0], "add")) {
        if (args.len < 2 or args.len > 3) {
            try stderr.writeAll("error: plugin add expects <git_or_path> [project_root]\n");
            return error.InvalidArguments;
        }
        const project_root = if (args.len == 3) args[2] else ".";
        return add(arena, io, stderr, stdout, args[1], project_root);
    }

    try stderr.print("error: unknown plugin command '{s}'\n", .{args[0]});
    return error.InvalidArguments;
}

pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        "Plugin:\n" ++
            "  ziggy plugin validate <ziggy-plugin.json>\n" ++
            "  ziggy plugin sync [project_root]\n" ++
            "  ziggy plugin add <git_or_path> [project_root]\n" ++
            "\n",
    );
}

fn validate(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    file_path: []const u8,
) !void {
    const manifest_text = std.Io.Dir.cwd().readFileAlloc(io, file_path, arena, .limited(1024 * 1024)) catch |err| {
        try stderr.print("error: failed to read '{s}': {s}\n", .{ file_path, @errorName(err) });
        return error.PluginFailed;
    };

    var manifest = ziggy_core.PluginManifest.parse(arena, manifest_text) catch |err| {
        try stderr.print("error: invalid plugin manifest '{s}': {s}\n", .{ file_path, @errorName(err) });
        return error.PluginFailed;
    };
    defer manifest.deinit(arena);

    try stdout.print(
        "valid plugin '{s}' version {s} schema v{d} (api {d}) with {d} capabilities\n",
        .{ manifest.id, manifest.version, manifest.schema_version, manifest.api_version, manifest.capabilities.len },
    );
    try stdout.flush();
}

fn sync(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root_raw: []const u8,
) !void {
    const project_root = try path_util.resolveAbsolute(arena, io, project_root_raw);
    const plugin_root = try path_util.join(arena, project_root, "plugins");
    const registry_dir = try path_util.join(arena, project_root, ".ziggy/plugins");
    const generated_dir = try path_util.join(arena, project_root, ".ziggy/generated");
    const swift_dir = try path_util.join(arena, generated_dir, "swift");
    const kotlin_dir = try path_util.join(arena, generated_dir, "kotlin/dev/ziggy");
    const zig_dir = try path_util.join(arena, generated_dir, "zig");

    for (&[_][]const u8{ registry_dir, swift_dir, kotlin_dir, zig_dir }) |dir_path| {
        try fs_util.ensureDir(io, dir_path);
    }

    var registry = ziggy_core.collectPluginRegistry(arena, io, plugin_root) catch |err| {
        try stderr.print("error: failed to collect plugins from '{s}': {s}\n", .{ plugin_root, @errorName(err) });
        return error.PluginFailed;
    };
    defer registry.deinit(arena);

    const lockfile = ziggy_core.renderPluginLockfile(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render lockfile: {s}\n", .{@errorName(err)});
        return error.PluginFailed;
    };
    const zig_registrant = ziggy_core.renderZigRegistrant(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render Zig registrant: {s}\n", .{@errorName(err)});
        return error.PluginFailed;
    };
    const swift_registrant = ziggy_core.renderSwiftRegistrant(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render Swift registrant: {s}\n", .{@errorName(err)});
        return error.PluginFailed;
    };
    const kotlin_registrant = ziggy_core.renderKotlinRegistrant(arena, registry.records) catch |err| {
        try stderr.print("error: failed to render Kotlin registrant: {s}\n", .{@errorName(err)});
        return error.PluginFailed;
    };

    const lockfile_path = try path_util.join(arena, registry_dir, "plugins.lock.toml");
    const zig_path = try path_util.join(arena, zig_dir, "generated_plugins.zig");
    const swift_path = try path_util.join(arena, swift_dir, "GeneratedPluginRegistrant.swift");
    const kotlin_path = try path_util.join(arena, kotlin_dir, "GeneratedPluginRegistrant.kt");
    const sdk_swift_path = try path_util.join(arena, project_root, ".ziggy/sdk/ios/Sources/Ziggy/GeneratedPluginRegistrant.swift");
    const sdk_kotlin_path = try path_util.join(arena, project_root, ".ziggy/sdk/android/src/main/kotlin/dev/ziggy/GeneratedPluginRegistrant.kt");

    try fs_util.writeFileAtomically(io, lockfile_path, lockfile);
    try fs_util.writeFileAtomically(io, zig_path, zig_registrant);
    try fs_util.writeFileAtomically(io, swift_path, swift_registrant);
    try fs_util.writeFileAtomically(io, kotlin_path, kotlin_registrant);
    if (fs_util.pathExists(io, try path_util.join(arena, project_root, ".ziggy/sdk/ios/Sources/Ziggy"))) {
        try fs_util.writeFileAtomically(io, sdk_swift_path, swift_registrant);
    }
    if (fs_util.pathExists(io, try path_util.join(arena, project_root, ".ziggy/sdk/android/src/main/kotlin/dev/ziggy"))) {
        try fs_util.writeFileAtomically(io, sdk_kotlin_path, kotlin_registrant);
    }

    try updateManagedPluginSections(arena, io, project_root, registry.records);

    try stdout.print(
        "generated {d} plugins\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n- {s}\n",
        .{ registry.records.len, lockfile_path, zig_path, swift_path, kotlin_path, sdk_swift_path, sdk_kotlin_path },
    );
    try stdout.flush();
}

fn add(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    source: []const u8,
    project_root_raw: []const u8,
) !void {
    const project_root = try path_util.resolveAbsolute(arena, io, project_root_raw);
    const plugins_dir = try path_util.join(arena, project_root, "plugins");
    try fs_util.ensureDir(io, plugins_dir);

    if (isLikelyGitSource(source)) {
        const base_name = repoNameFromSource(source);
        const destination = try path_util.join(arena, plugins_dir, base_name);
        _ = process_util.runChecked(
            arena,
            io,
            stderr,
            null,
            &.{ "git", "clone", source, destination },
            null,
            "clone plugin repository",
        ) catch {
            try stderr.writeAll("error: failed to clone plugin; check repository access\n");
            return error.PluginFailed;
        };
        try stdout.print("added plugin from git: {s}\n", .{destination});
        return;
    }

    const src_abs = try path_util.resolveAbsolute(arena, io, source);
    const base_name = std.fs.path.basename(src_abs);
    const destination = try path_util.join(arena, plugins_dir, base_name);

    fs_util.removeTreeIfExists(io, destination) catch {};
    try fs_util.copyTree(arena, io, src_abs, destination);

    const manifest_path = try path_util.join(arena, destination, "ziggy-plugin.json");
    if (!fs_util.pathExists(io, manifest_path)) {
        try stderr.print("error: added plugin has no ziggy-plugin.json at '{s}'\n", .{manifest_path});
        return error.PluginFailed;
    }

    try stdout.print("added plugin from path: {s}\n", .{destination});
    try stdout.flush();
}

fn updateManagedPluginSections(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    records: []const ziggy_core.PluginRecord,
) !void {
    const ios_project_yml = try path_util.join(arena, project_root, "ios/project.yml");
    const android_app_build = try path_util.join(arena, project_root, "android/app/build.gradle.kts");

    if (fs_util.pathExists(io, ios_project_yml)) {
        var lines = std.ArrayList(u8).empty;
        defer lines.deinit(arena);
        try lines.appendSlice(arena, "# ZIGGY_MANAGED_PLUGINS_BEGIN\n");
        for (records) |record| {
            for (record.manifest.ios_spm) |dep| {
                try lines.appendSlice(arena, "# SPM: ");
                try lines.appendSlice(arena, dep.url);
                try lines.appendSlice(arena, " @ ");
                try lines.appendSlice(arena, dep.requirement);
                try lines.appendSlice(arena, " product=");
                try lines.appendSlice(arena, dep.product);
                try lines.appendSlice(arena, "\n");
            }
        }
        try lines.appendSlice(arena, "# ZIGGY_MANAGED_PLUGINS_END\n");
        try injectManagedBlock(arena, io, ios_project_yml, "# ZIGGY_MANAGED_PLUGINS_BEGIN", "# ZIGGY_MANAGED_PLUGINS_END", lines.items);
    }

    if (fs_util.pathExists(io, android_app_build)) {
        var lines = std.ArrayList(u8).empty;
        defer lines.deinit(arena);
        try lines.appendSlice(arena, "// ZIGGY_MANAGED_PLUGINS_BEGIN\n");
        for (records) |record| {
            for (record.manifest.android_maven) |dep| {
                try lines.appendSlice(arena, "// MAVEN: ");
                try lines.appendSlice(arena, dep.coordinate);
                try lines.appendSlice(arena, " scope=");
                try lines.appendSlice(arena, dep.scope);
                if (dep.classifier.len > 0) {
                    try lines.appendSlice(arena, " classifier=");
                    try lines.appendSlice(arena, dep.classifier);
                }
                try lines.appendSlice(arena, "\n");
            }
        }
        try lines.appendSlice(arena, "// ZIGGY_MANAGED_PLUGINS_END\n");
        try injectManagedBlock(arena, io, android_app_build, "// ZIGGY_MANAGED_PLUGINS_BEGIN", "// ZIGGY_MANAGED_PLUGINS_END", lines.items);
    }
}

fn injectManagedBlock(
    arena: std.mem.Allocator,
    io: std.Io,
    file_path: []const u8,
    begin_marker: []const u8,
    end_marker: []const u8,
    block: []const u8,
) !void {
    const original = try std.Io.Dir.cwd().readFileAlloc(io, file_path, arena, .limited(2 * 1024 * 1024));

    const begin_pos = std.mem.indexOf(u8, original, begin_marker);
    const end_pos = std.mem.indexOf(u8, original, end_marker);

    var rendered = std.ArrayList(u8).empty;
    defer rendered.deinit(arena);

    if (begin_pos != null and end_pos != null and begin_pos.? < end_pos.?) {
        try rendered.appendSlice(arena, original[0..begin_pos.?]);
        try rendered.appendSlice(arena, block);
        const suffix_start = end_pos.? + end_marker.len;
        if (suffix_start < original.len) {
            try rendered.appendSlice(arena, original[suffix_start..]);
        }
    } else {
        try rendered.appendSlice(arena, original);
        if (!std.mem.endsWith(u8, original, "\n")) {
            try rendered.append(arena, '\n');
        }
        try rendered.appendSlice(arena, block);
    }

    try fs_util.writeFileAtomically(io, file_path, rendered.items);
}

fn isLikelyGitSource(source: []const u8) bool {
    return std.mem.startsWith(u8, source, "https://") or
        std.mem.startsWith(u8, source, "git@") or
        std.mem.endsWith(u8, source, ".git");
}

fn repoNameFromSource(source: []const u8) []const u8 {
    const base = std.fs.path.basename(source);
    if (std.mem.endsWith(u8, base, ".git") and base.len > 4) {
        return base[0 .. base.len - 4];
    }
    return base;
}
