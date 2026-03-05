//! Shared parsing helpers used by Zig and JSON contract parsers.

const std = @import("std");
const api = @import("../model/api.zig");

/// Resolves a type token to an API type.
///
/// ## Accepted Tokens
/// - primitive aliases: `string`, `int`, `bool`, `void`
/// - discovered type names from `known_struct_names` / `known_enum_names`
pub fn parseTypeTokenWithKnown(
    token_raw: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) !api.ApiType {
    const token = std.mem.trim(u8, token_raw, " \t\r\n");
    if (std.mem.eql(u8, token, "string")) return .string;
    if (std.mem.eql(u8, token, "int")) return .int;
    if (std.mem.eql(u8, token, "bool")) return .bool;
    if (std.mem.eql(u8, token, "void")) return .void;

    for (known_struct_names) |name| {
        if (std.mem.eql(u8, token, name)) return .{ .user_struct = name };
    }
    for (known_enum_names) |name| {
        if (std.mem.eql(u8, token, name)) return .{ .user_enum = name };
    }
    return error.InvalidContract;
}

/// Duplicates a required non-empty JSON string field.
pub fn dupRequiredString(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    field: []const u8,
) ![]u8 {
    const value = object.get(field) orelse return error.InvalidContract;
    if (value != .string or value.string.len == 0) return error.InvalidContract;
    return allocator.dupe(u8, value.string);
}
