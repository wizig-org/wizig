//! Parsing helpers for user type discovery.
//!
//! ## Scope
//! - Extract public `struct`/`enum` declarations from Zig source text.
//! - Parse struct fields and enum variants into `ApiSpec` model types.
//! - Resolve field type tokens using known discovered type-name registries.

const std = @import("std");
const api = @import("../model/api.zig");

/// Lightweight list of discovered type names from one source file.
pub const ParsedTypeNames = struct {
    struct_names: []const []const u8,
    enum_names: []const []const u8,
};

/// Collects top-level `pub const <Name> = struct|enum ...` declarations.
pub fn collectTypeNamesFromSource(arena: std.mem.Allocator, source: []const u8) !ParsedTypeNames {
    var struct_names = std.ArrayList([]const u8).empty;
    var enum_names = std.ArrayList([]const u8).empty;

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "pub const ")) |start| {
        cursor = start + "pub const ".len;
        const name_start = cursor;
        while (cursor < source.len and isIdentChar(source[cursor])) : (cursor += 1) {}
        const name = source[name_start..cursor];
        if (!isValidIdent(name)) continue;

        while (cursor < source.len and source[cursor] == ' ') : (cursor += 1) {}
        const rest = source[cursor..];
        if (std.mem.startsWith(u8, rest, "= struct {")) {
            try struct_names.append(arena, try arena.dupe(u8, name));
            continue;
        }
        if (std.mem.startsWith(u8, rest, "= enum {") or std.mem.startsWith(u8, rest, "= enum(")) {
            try enum_names.append(arena, try arena.dupe(u8, name));
        }
    }

    return .{
        .struct_names = try struct_names.toOwnedSlice(arena),
        .enum_names = try enum_names.toOwnedSlice(arena),
    };
}

/// Parses all public struct declarations from `source`.
pub fn parseStructsFromSource(
    arena: std.mem.Allocator,
    source: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.UserStruct {
    var result = std.ArrayList(api.UserStruct).empty;
    var cursor: usize = 0;

    while (std.mem.indexOfPos(u8, source, cursor, "pub const ")) |start| {
        cursor = start + "pub const ".len;
        const name_start = cursor;
        while (cursor < source.len and isIdentChar(source[cursor])) : (cursor += 1) {}
        const name = source[name_start..cursor];
        if (!isValidIdent(name)) continue;

        while (cursor < source.len and source[cursor] == ' ') : (cursor += 1) {}
        if (!std.mem.startsWith(u8, source[cursor..], "= struct {")) continue;
        cursor += "= struct {".len;

        const body = extractDelimitedBody(source, &cursor) orelse break;
        const fields = try parseStructFields(arena, body, known_struct_names, known_enum_names);
        if (fields.len == 0) continue;

        try result.append(arena, .{
            .name = try arena.dupe(u8, name),
            .fields = fields,
        });
    }

    return result.toOwnedSlice(arena);
}

/// Parses all public enum declarations from `source`.
pub fn parseEnumsFromSource(arena: std.mem.Allocator, source: []const u8) ![]const api.UserEnum {
    var result = std.ArrayList(api.UserEnum).empty;
    var cursor: usize = 0;

    while (std.mem.indexOfPos(u8, source, cursor, "pub const ")) |start| {
        cursor = start + "pub const ".len;
        const name_start = cursor;
        while (cursor < source.len and isIdentChar(source[cursor])) : (cursor += 1) {}
        const name = source[name_start..cursor];
        if (!isValidIdent(name)) continue;

        while (cursor < source.len and source[cursor] == ' ') : (cursor += 1) {}
        const rest = source[cursor..];
        if (!std.mem.startsWith(u8, rest, "= enum {") and !std.mem.startsWith(u8, rest, "= enum(")) continue;
        const open_brace = std.mem.indexOfScalar(u8, rest, '{') orelse continue;
        cursor += open_brace + 1;

        const body = extractDelimitedBody(source, &cursor) orelse break;
        const variants = try parseEnumVariants(arena, body);
        if (variants.len == 0) continue;

        try result.append(arena, .{
            .name = try arena.dupe(u8, name),
            .variants = variants,
        });
    }

    return result.toOwnedSlice(arena);
}

/// Resolves a field type token against primitive and discovered type registries.
pub fn parseFieldType(
    token: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ?api.ApiType {
    var normalized: [256]u8 = undefined;
    var len: usize = 0;
    for (token) |ch| {
        if (std.ascii.isWhitespace(ch)) continue;
        if (len >= normalized.len) return null;
        normalized[len] = ch;
        len += 1;
    }
    const ty = normalized[0..len];
    if (std.mem.eql(u8, ty, "[]constu8") or std.mem.eql(u8, ty, "[]u8")) return .string;
    if (std.mem.eql(u8, ty, "i64")) return .int;
    if (std.mem.eql(u8, ty, "bool")) return .bool;

    const base = if (std.mem.lastIndexOfScalar(u8, ty, '.')) |dot| ty[dot + 1 ..] else ty;
    for (known_struct_names) |name| {
        if (std.mem.eql(u8, base, name)) return .{ .user_struct = name };
    }
    for (known_enum_names) |name| {
        if (std.mem.eql(u8, base, name)) return .{ .user_enum = name };
    }
    return null;
}

fn parseStructFields(
    arena: std.mem.Allocator,
    body: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.StructField {
    var fields = std.ArrayList(api.StructField).empty;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or std.mem.startsWith(u8, line, "//")) continue;
        if (std.mem.startsWith(u8, line, "pub fn ") or std.mem.startsWith(u8, line, "fn ")) continue;

        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const field_name = std.mem.trim(u8, line[0..colon], " \t");
        if (!isValidIdent(field_name)) continue;

        var type_part = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.mem.indexOfScalar(u8, type_part, '=')) |eq| {
            type_part = std.mem.trim(u8, type_part[0..eq], " \t");
        }
        if (type_part.len > 0 and type_part[type_part.len - 1] == ',') {
            type_part = std.mem.trim(u8, type_part[0 .. type_part.len - 1], " \t");
        }

        const resolved = parseFieldType(type_part, known_struct_names, known_enum_names) orelse continue;
        try fields.append(arena, .{
            .name = try arena.dupe(u8, field_name),
            .field_type = resolved,
        });
    }
    return fields.toOwnedSlice(arena);
}

fn parseEnumVariants(arena: std.mem.Allocator, body: []const u8) ![]const []const u8 {
    var variants = std.ArrayList([]const u8).empty;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        var line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or std.mem.startsWith(u8, line, "//")) continue;
        if (std.mem.startsWith(u8, line, "pub fn ") or std.mem.startsWith(u8, line, "fn ")) continue;
        if (line[0] == '@') continue;

        if (std.mem.indexOfScalar(u8, line, '=')) |eq| line = std.mem.trim(u8, line[0..eq], " \t");
        if (line.len > 0 and line[line.len - 1] == ',') line = std.mem.trim(u8, line[0 .. line.len - 1], " \t");
        if (!isValidIdent(line)) continue;
        try variants.append(arena, try arena.dupe(u8, line));
    }
    return variants.toOwnedSlice(arena);
}

fn extractDelimitedBody(source: []const u8, cursor: *usize) ?[]const u8 {
    var depth: usize = 1;
    const body_start = cursor.*;
    while (cursor.* < source.len and depth > 0) : (cursor.* += 1) {
        switch (source[cursor.*]) {
            '{' => depth += 1,
            '}' => depth -= 1,
            else => {},
        }
    }
    if (depth != 0 or cursor.* == 0) return null;
    return source[body_start .. cursor.* - 1];
}

fn isIdentChar(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_';
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

fn isValidIdent(s: []const u8) bool {
    if (s.len == 0 or !isIdentStart(s[0])) return false;
    for (s[1..]) |ch| {
        if (!isIdentChar(ch)) return false;
    }
    return true;
}
