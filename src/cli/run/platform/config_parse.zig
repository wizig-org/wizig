//! Lightweight parsers for Android manifest/Gradle and iOS build settings.
//!
//! These helpers intentionally avoid heavy dependencies and focus on extracting
//! the specific fields needed by the run pipeline.
const std = @import("std");

/// Extracts a key from `xcodebuild -showBuildSettings` output.
pub fn extractBuildSetting(settings: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, settings, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len <= key.len + 3) continue;
        if (!std.mem.startsWith(u8, line, key)) continue;
        if (line[key.len] != ' ') continue;
        if (line[key.len + 1] != '=') continue;
        if (line[key.len + 2] != ' ') continue;
        return line[key.len + 3 ..];
    }
    return null;
}

/// Extracts an XML attribute from the first matching element tag.
pub fn extractXmlAttribute(xml: []const u8, tag_name: []const u8, attr_name: []const u8) ?[]const u8 {
    var cursor: usize = 0;
    while (cursor < xml.len) {
        const open = std.mem.indexOfPos(u8, xml, cursor, "<") orelse return null;
        const close = std.mem.indexOfPos(u8, xml, open, ">") orelse return null;
        const element = xml[open + 1 .. close];
        cursor = close + 1;

        if (element.len == 0 or element[0] == '/' or element[0] == '!' or element[0] == '?') continue;
        if (!std.mem.startsWith(u8, element, tag_name)) continue;
        if (element.len > tag_name.len and !std.ascii.isWhitespace(element[tag_name.len])) continue;

        var attr_it = std.mem.splitAny(u8, element, " \t\r\n");
        _ = attr_it.next();
        while (attr_it.next()) |token| {
            if (!std.mem.startsWith(u8, token, attr_name)) continue;
            if (token.len <= attr_name.len + 2) continue;
            if (token[attr_name.len] != '=') continue;
            if (token[attr_name.len + 1] != '"') continue;
            const rest = token[attr_name.len + 2 ..];
            const quote_end = std.mem.indexOfScalar(u8, rest, '"') orelse continue;
            return rest[0..quote_end];
        }
    }
    return null;
}

/// Extracts a Kotlin-DSL style `key = "value"` declaration.
pub fn extractGradleStringValue(content: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, key)) continue;
        const quote_start = std.mem.indexOfScalar(u8, line, '"') orelse continue;
        const rest = line[quote_start + 1 ..];
        const quote_end = std.mem.indexOfScalar(u8, rest, '"') orelse continue;
        return rest[0..quote_end];
    }
    return null;
}

/// Derives Xcode scheme name from `.xcodeproj` folder name.
pub fn inferSchemeFromProject(project_path: []const u8) ?[]const u8 {
    const base = std.fs.path.basename(project_path);
    if (!std.mem.endsWith(u8, base, ".xcodeproj")) return null;
    return base[0 .. base.len - ".xcodeproj".len];
}

/// Converts `com.app.Activity` or `.Activity` into `app/.Activity` component.
pub fn normalizeAndroidComponent(
    arena: std.mem.Allocator,
    app_id: []const u8,
    activity: []const u8,
) ![]const u8 {
    if (std.mem.containsAtLeast(u8, activity, 1, "/")) {
        return arena.dupe(u8, activity);
    }
    if (std.mem.startsWith(u8, activity, ".")) {
        return std.fmt.allocPrint(arena, "{s}/{s}", .{ app_id, activity });
    }
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ app_id, activity });
}
