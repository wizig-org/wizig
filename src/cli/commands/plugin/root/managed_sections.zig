//! Managed block rendering and file rewriting for plugin metadata sync.
const std = @import("std");

const fs_util = @import("../../../support/fs.zig");
const path_util = @import("../../../support/path.zig");
const wizig_core = @import("wizig_core");

/// Rewrites managed plugin sections in project files when they exist.
pub fn updateManagedPluginSections(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    records: []const wizig_core.PluginRecord,
) !void {
    const ios_project_yml = try path_util.join(arena, project_root, "ios/project.yml");
    const android_app_build = try path_util.join(arena, project_root, "android/app/build.gradle.kts");

    if (fs_util.pathExists(io, ios_project_yml)) {
        const block = try renderIosManagedPluginBlock(arena, records);
        try applyManagedBlock(arena, io, ios_project_yml, "# WIZIG_MANAGED_PLUGINS_BEGIN", "# WIZIG_MANAGED_PLUGINS_END", block);
    }

    if (fs_util.pathExists(io, android_app_build)) {
        const block = try renderAndroidManagedPluginBlock(arena, records);
        try applyManagedBlock(arena, io, android_app_build, "// WIZIG_MANAGED_PLUGINS_BEGIN", "// WIZIG_MANAGED_PLUGINS_END", block);
    }
}

/// Renders the iOS managed section body with Wizig-specific comment markers.
pub fn renderIosManagedPluginBlock(
    arena: std.mem.Allocator,
    records: []const wizig_core.PluginRecord,
) ![]u8 {
    var lines = std.ArrayList(u8).empty;
    errdefer lines.deinit(arena);

    try lines.appendSlice(arena, "# WIZIG_MANAGED_PLUGINS_BEGIN\n");
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
    try lines.appendSlice(arena, "# WIZIG_MANAGED_PLUGINS_END\n");
    return lines.toOwnedSlice(arena);
}

/// Renders the Android managed section body with Wizig-specific comment markers.
pub fn renderAndroidManagedPluginBlock(
    arena: std.mem.Allocator,
    records: []const wizig_core.PluginRecord,
) ![]u8 {
    var lines = std.ArrayList(u8).empty;
    errdefer lines.deinit(arena);

    try lines.appendSlice(arena, "// WIZIG_MANAGED_PLUGINS_BEGIN\n");
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
    try lines.appendSlice(arena, "// WIZIG_MANAGED_PLUGINS_END\n");
    return lines.toOwnedSlice(arena);
}

/// Returns `original` with the managed block replaced or appended.
pub fn renderManagedBlockText(
    arena: std.mem.Allocator,
    original: []const u8,
    begin_marker: []const u8,
    end_marker: []const u8,
    block: []const u8,
) ![]u8 {
    const begin_pos = std.mem.indexOf(u8, original, begin_marker);
    const end_pos = std.mem.indexOf(u8, original, end_marker);

    var rendered = std.ArrayList(u8).empty;
    errdefer rendered.deinit(arena);

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

    return rendered.toOwnedSlice(arena);
}

fn applyManagedBlock(
    arena: std.mem.Allocator,
    io: std.Io,
    file_path: []const u8,
    begin_marker: []const u8,
    end_marker: []const u8,
    block: []const u8,
) !void {
    const original = try std.Io.Dir.cwd().readFileAlloc(io, file_path, arena, .limited(2 * 1024 * 1024));
    const rendered = try renderManagedBlockText(arena, original, begin_marker, end_marker, block);
    try fs_util.writeFileAtomically(io, file_path, rendered);
}

test "renderManagedBlockText replaces an existing managed section" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const original =
        \\header
        \\# WIZIG_MANAGED_PLUGINS_BEGIN
        \\old
        \\# WIZIG_MANAGED_PLUGINS_END
        \\footer
    ;
    const block =
        \\# WIZIG_MANAGED_PLUGINS_BEGIN
        \\managed
        \\# WIZIG_MANAGED_PLUGINS_END
    ;
    const rendered = try renderManagedBlockText(arena, original, "# WIZIG_MANAGED_PLUGINS_BEGIN", "# WIZIG_MANAGED_PLUGINS_END", block);
    try std.testing.expectEqualStrings(
        \\header
        \\# WIZIG_MANAGED_PLUGINS_BEGIN
        \\managed
        \\# WIZIG_MANAGED_PLUGINS_END
        \\footer
    , rendered);
}

test "renderManagedBlockText appends a managed section when markers are absent" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const rendered = try renderManagedBlockText(arena, "header", "# WIZIG_MANAGED_PLUGINS_BEGIN", "# WIZIG_MANAGED_PLUGINS_END", "# WIZIG_MANAGED_PLUGINS_BEGIN\nmanaged\n# WIZIG_MANAGED_PLUGINS_END\n");
    try std.testing.expectEqualStrings(
        \\header
        \\# WIZIG_MANAGED_PLUGINS_BEGIN
        \\managed
        \\# WIZIG_MANAGED_PLUGINS_END
        \\
    , rendered);
}
