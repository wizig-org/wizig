//! Zig contract parser (`wizig.api.zig`).
//!
//! ## Supported Shape
//! - `pub const namespace = "...";`
//! - `pub const methods = .{ .{ ... }, ... };`
//! - `pub const events = .{ .{ ... }, ... };`
//! - `pub const structs = .{ .{ .name, .fields = .{ ... } }, ... };`
//! - `pub const enums = .{ .{ .name, .variants = .{ ... } }, ... };`

const std = @import("std");
const api = @import("../model/api.zig");
const shared = @import("parse_shared.zig");

/// Parses a Zig contract into `ApiSpec`.
pub fn parseApiSpecFromZig(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
    const namespace = try extractQuotedField(arena, text, "pub const namespace = \"");

    const known_struct_names = try parseTypeNamesFromSection(arena, text, "pub const structs = .{");
    const known_enum_names = try parseTypeNamesFromSection(arena, text, "pub const enums = .{");

    const methods = try parseMethods(arena, text, known_struct_names, known_enum_names);
    const events = try parseEvents(arena, text, known_struct_names, known_enum_names);
    const structs = try parseStructs(arena, text, known_struct_names, known_enum_names);
    const enums = try parseEnums(arena, text);

    return .{
        .namespace = namespace,
        .methods = methods,
        .events = events,
        .structs = structs,
        .enums = enums,
    };
}

fn parseTypeNamesFromSection(
    arena: std.mem.Allocator,
    text: []const u8,
    section_marker: []const u8,
) ![]const []const u8 {
    const body = findSectionBody(text, section_marker) orelse return &.{};
    const entries = try collectObjectBodies(arena, body);

    var names = std.ArrayList([]const u8).empty;
    for (entries) |entry| {
        try names.append(arena, try extractQuotedField(arena, entry, ".name = \""));
    }
    return names.toOwnedSlice(arena);
}

fn parseMethods(
    arena: std.mem.Allocator,
    text: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.ApiMethod {
    const body = findSectionBody(text, "pub const methods = .{") orelse return &.{};
    const entries = try collectObjectBodies(arena, body);

    var methods = std.ArrayList(api.ApiMethod).empty;
    for (entries) |entry| {
        const name = try extractQuotedField(arena, entry, ".name = \"");
        const input = try parseTypeFieldWithKnown(arena, entry, ".input = ", known_struct_names, known_enum_names);
        const output = try parseTypeFieldWithKnown(arena, entry, ".output = ", known_struct_names, known_enum_names);
        try methods.append(arena, .{ .name = name, .input = input, .output = output });
    }
    return methods.toOwnedSlice(arena);
}

fn parseEvents(
    arena: std.mem.Allocator,
    text: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.ApiEvent {
    const body = findSectionBody(text, "pub const events = .{") orelse return &.{};
    const entries = try collectObjectBodies(arena, body);

    var events = std.ArrayList(api.ApiEvent).empty;
    for (entries) |entry| {
        const name = try extractQuotedField(arena, entry, ".name = \"");
        const payload = try parseTypeFieldWithKnown(arena, entry, ".payload = ", known_struct_names, known_enum_names);
        try events.append(arena, .{ .name = name, .payload = payload });
    }
    return events.toOwnedSlice(arena);
}

fn parseStructs(
    arena: std.mem.Allocator,
    text: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.UserStruct {
    const body = findSectionBody(text, "pub const structs = .{") orelse return &.{};
    const entries = try collectObjectBodies(arena, body);

    var structs = std.ArrayList(api.UserStruct).empty;
    for (entries) |entry| {
        const name = try extractQuotedField(arena, entry, ".name = \"");
        const fields_body = findSectionBody(entry, ".fields = .{") orelse "";
        const field_entries = try collectObjectBodies(arena, fields_body);

        var fields = std.ArrayList(api.StructField).empty;
        for (field_entries) |field_entry| {
            const field_name = try extractQuotedField(arena, field_entry, ".name = \"");
            const field_type = try parseTypeFieldWithKnown(arena, field_entry, ".field_type = ", known_struct_names, known_enum_names);
            try fields.append(arena, .{ .name = field_name, .field_type = field_type });
        }

        try structs.append(arena, .{
            .name = name,
            .fields = try fields.toOwnedSlice(arena),
        });
    }

    return structs.toOwnedSlice(arena);
}

fn parseEnums(arena: std.mem.Allocator, text: []const u8) ![]const api.UserEnum {
    const body = findSectionBody(text, "pub const enums = .{") orelse return &.{};
    const entries = try collectObjectBodies(arena, body);

    var enums = std.ArrayList(api.UserEnum).empty;
    for (entries) |entry| {
        const name = try extractQuotedField(arena, entry, ".name = \"");
        const variants_body = findSectionBody(entry, ".variants = .{") orelse "";
        const variants = try collectQuotedStrings(arena, variants_body);
        try enums.append(arena, .{
            .name = name,
            .variants = variants,
        });
    }
    return enums.toOwnedSlice(arena);
}

fn parseTypeFieldWithKnown(
    arena: std.mem.Allocator,
    entry: []const u8,
    marker: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) !api.ApiType {
    const start = std.mem.indexOf(u8, entry, marker) orelse return error.InvalidContract;
    const rest = std.mem.trim(u8, entry[start + marker.len ..], " \t\r\n");

    if (std.mem.startsWith(u8, rest, ".{")) {
        if (std.mem.indexOf(u8, rest, ".user_struct = \"")) |_| {
            const name = try extractQuotedField(arena, rest, ".user_struct = \"");
            return .{ .user_struct = name };
        }
        if (std.mem.indexOf(u8, rest, ".user_enum = \"")) |_| {
            const name = try extractQuotedField(arena, rest, ".user_enum = \"");
            return .{ .user_enum = name };
        }
        return error.InvalidContract;
    }

    if (!std.mem.startsWith(u8, rest, ".")) return error.InvalidContract;
    const token = readIdent(rest[1..]) orelse return error.InvalidContract;
    return shared.parseTypeTokenWithKnown(token, known_struct_names, known_enum_names);
}

fn findSectionBody(haystack: []const u8, section_marker: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, haystack, section_marker) orelse return null;
    var cursor = start + section_marker.len;
    const body_start = cursor;
    var depth: usize = 1;
    while (cursor < haystack.len and depth > 0) : (cursor += 1) {
        switch (haystack[cursor]) {
            '{' => depth += 1,
            '}' => depth -= 1,
            else => {},
        }
    }
    if (depth != 0 or cursor == 0) return null;
    return haystack[body_start .. cursor - 1];
}

fn collectObjectBodies(arena: std.mem.Allocator, section_body: []const u8) ![]const []const u8 {
    var out = std.ArrayList([]const u8).empty;
    var index: usize = 0;
    var entry_start: ?usize = null;
    var depth: usize = 0;

    while (index < section_body.len) : (index += 1) {
        if (entry_start == null) {
            if (section_body[index] == '.' and index + 1 < section_body.len and section_body[index + 1] == '{') {
                entry_start = index + 1;
                depth = 1;
                index += 1;
            }
            continue;
        }

        switch (section_body[index]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) {
                    const start = entry_start.?;
                    try out.append(arena, section_body[start + 1 .. index]);
                    entry_start = null;
                }
            },
            else => {},
        }
    }

    return out.toOwnedSlice(arena);
}

fn collectQuotedStrings(arena: std.mem.Allocator, body: []const u8) ![]const []const u8 {
    var values = std.ArrayList([]const u8).empty;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, body, cursor, "\"")) |start| {
        const value_start = start + 1;
        const end = std.mem.indexOfPos(u8, body, value_start, "\"") orelse return error.InvalidContract;
        try values.append(arena, try arena.dupe(u8, body[value_start..end]));
        cursor = end + 1;
    }
    return values.toOwnedSlice(arena);
}

fn extractQuotedField(arena: std.mem.Allocator, line: []const u8, prefix: []const u8) ![]u8 {
    const start = std.mem.indexOf(u8, line, prefix) orelse return error.InvalidContract;
    const rest = line[start + prefix.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return error.InvalidContract;
    if (end == 0) return error.InvalidContract;
    return arena.dupe(u8, rest[0..end]);
}

fn readIdent(input: []const u8) ?[]const u8 {
    var end: usize = 0;
    while (end < input.len) : (end += 1) {
        const ch = input[end];
        if (!(std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_')) break;
    }
    if (end == 0) return null;
    return input[0..end];
}
