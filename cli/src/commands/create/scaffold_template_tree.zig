//! Template tree rendering for host scaffolds.
//!
//! The helpers in this file walk template directories, apply content/path token
//! replacements, and materialize output trees while honoring overwrite policy.
const std = @import("std");

const fs_util = @import("../../support/fs.zig");
const scaffold_util = @import("scaffold_util.zig");

/// Token replacement rule for path segments.
///
/// Keys and values are matched as raw byte slices and applied in-order.
pub const PathToken = struct {
    key: []const u8,
    value: []const u8,
};

/// Copies a template tree and renders file/path placeholders.
///
/// - Directory entries are created recursively.
/// - Text files are rendered using template content tokens.
/// - Binary files are copied byte-for-byte.
/// - Existing files are skipped unless `force_overwrite` is true.
pub fn copyTemplateTreeRendered(
    arena: std.mem.Allocator,
    io: std.Io,
    src_root: []const u8,
    dst_root: []const u8,
    tokens: []const fs_util.RenderToken,
    path_tokens: []const PathToken,
    force_overwrite: bool,
) !void {
    var src_dir = try std.Io.Dir.cwd().openDir(io, src_root, .{ .iterate = true });
    defer src_dir.close(io);

    try std.Io.Dir.cwd().createDirPath(io, dst_root);
    var walker = try src_dir.walk(arena);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (shouldSkipTemplateEntry(entry.path)) continue;

        const rendered_rel = try renderPathTokens(arena, entry.path, path_tokens);
        const src_path = try scaffold_util.joinPath(arena, src_root, entry.path);
        const dst_path = try scaffold_util.joinPath(arena, dst_root, rendered_rel);

        switch (entry.kind) {
            .directory => try std.Io.Dir.cwd().createDirPath(io, dst_path),
            .file => {
                if (!force_overwrite and fs_util.pathExists(io, dst_path)) {
                    continue;
                }

                const bytes = try std.Io.Dir.cwd().readFileAlloc(io, src_path, arena, .limited(256 * 1024 * 1024));
                if (isTemplateTextFile(src_path, bytes)) {
                    const rendered = try fs_util.renderTemplate(arena, bytes, tokens);
                    try fs_util.writeFileAtomically(io, dst_path, rendered);
                } else {
                    try fs_util.writeFileAtomically(io, dst_path, bytes);
                }
            },
            else => {},
        }
    }
}

/// Applies path-token substitutions to a relative template path.
fn renderPathTokens(allocator: std.mem.Allocator, raw_path: []const u8, path_tokens: []const PathToken) ![]u8 {
    var rendered = try allocator.dupe(u8, raw_path);
    for (path_tokens) |token| {
        rendered = try replaceAllAlloc(allocator, rendered, token.key, token.value);
    }
    return rendered;
}

/// Returns an owned copy of `haystack` with all `needle` occurrences replaced.
fn replaceAllAlloc(
    allocator: std.mem.Allocator,
    haystack: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, haystack);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, cursor, needle)) |idx| {
        try out.appendSlice(allocator, haystack[cursor..idx]);
        try out.appendSlice(allocator, replacement);
        cursor = idx + needle.len;
    }
    try out.appendSlice(allocator, haystack[cursor..]);
    return out.toOwnedSlice(allocator);
}

/// Heuristically determines whether template bytes should be token-rendered.
///
/// Known text extensions are always considered renderable; unknown formats are
/// treated as text only if they are valid UTF-8 and contain no NUL bytes.
fn isTemplateTextFile(path: []const u8, bytes: []const u8) bool {
    const basename = std.fs.path.basename(path);
    if (std.mem.eql(u8, basename, "gradlew") or std.mem.eql(u8, basename, "gradlew.bat")) {
        return true;
    }

    const ext = std.fs.path.extension(path);
    for (template_text_extensions) |text_ext| {
        if (std.mem.eql(u8, ext, text_ext)) return true;
    }

    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return false;
    return std.unicode.utf8ValidateSlice(bytes);
}

/// Filters out template entries that should not be copied into app projects.
///
/// This prevents editor/gradle caches and seed-only metadata from leaking into
/// generated host directories.
fn shouldSkipTemplateEntry(entry_path: []const u8) bool {
    var it = std.mem.splitAny(u8, entry_path, "/\\");
    while (it.next()) |segment| {
        if (segment.len == 0) continue;
        if (std.mem.eql(u8, segment, "project.yml")) return true;
        if (std.mem.eql(u8, segment, "Sources")) return true;
        if (std.mem.eql(u8, segment, ".DS_Store")) return true;
        if (std.mem.eql(u8, segment, ".gradle")) return true;
        if (std.mem.eql(u8, segment, ".idea")) return true;
        if (std.mem.eql(u8, segment, "build")) return true;
    }
    return false;
}

const template_text_extensions = [_][]const u8{
    ".swift",
    ".pbxproj",
    ".plist",
    ".xcworkspacedata",
    ".kts",
    ".gradle",
    ".xml",
    ".kt",
    ".java",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".properties",
    ".md",
    ".txt",
    ".gitignore",
    ".pro",
};

 test "replaceAllAlloc substitutes repeated matches" {
    const out = try replaceAllAlloc(std.testing.allocator, "a__X__b__X__c", "__X__", "ZZ");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("aZZbZZc", out);
}

 test "isTemplateTextFile rejects nul bytes" {
    const bytes = [_]u8{ 'a', 0, 'b' };
    try std.testing.expect(!isTemplateTextFile("/tmp/thing.bin", &bytes));
}
