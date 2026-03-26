//! Shared JSON object access helpers for iOS discovery parsing.
const std = @import("std");

/// Returns a string value from a JSON object, or null when the field is absent or not a string.
pub fn objectString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

/// Returns a bool value from a JSON object, or null when the field is absent or not a bool.
pub fn objectBool(object: std.json.ObjectMap, key: []const u8) ?bool {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .bool => |v| v,
        else => null,
    };
}
