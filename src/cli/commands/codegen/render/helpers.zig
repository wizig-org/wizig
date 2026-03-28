//! Shared helpers for renderer modules.

const std = @import("std");
const api = @import("../model/api.zig");

/// Logical ABI wire categories used by generated host and bridge code.
pub const WireKind = enum {
    string,
    int,
    bool,
    void,
};

pub fn appendFmt(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const rendered = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(rendered);
    try out.appendSlice(allocator, rendered);
}

pub fn zigType(value: api.ApiType) []const u8 {
    return switch (value) {
        .string => "[]const u8",
        .int => "i64",
        .bool => "bool",
        .void => "void",
        .user_struct => |name| name,
        .user_enum => |name| name,
    };
}

pub fn swiftType(value: api.ApiType) []const u8 {
    return switch (value) {
        .string => "String",
        .int => "Int64",
        .bool => "Bool",
        .void => "Void",
        .user_struct => |name| name,
        .user_enum => |name| name,
    };
}

pub fn kotlinType(value: api.ApiType) []const u8 {
    return switch (value) {
        .string => "String",
        .int => "Long",
        .bool => "Boolean",
        .void => "Unit",
        .user_struct => |name| name,
        .user_enum => |name| name,
    };
}

pub fn jniCType(value: api.ApiType) []const u8 {
    return switch (wireKind(value)) {
        .string => "jstring",
        .int => "jlong",
        .bool => "jboolean",
        .void => "void",
    };
}

pub fn zigDefaultValue(value: api.ApiType) []const u8 {
    return switch (value) {
        .string => "\"\"",
        .int => "0",
        .bool => "false",
        .void => "{}",
        .user_struct => "undefined",
        .user_enum => "undefined",
    };
}

pub fn jniEscape(arena: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(arena);
    for (input) |ch| {
        switch (ch) {
            '_' => try out.appendSlice(arena, "_1"),
            ';' => try out.appendSlice(arena, "_2"),
            '[' => try out.appendSlice(arena, "_3"),
            else => try out.append(arena, ch),
        }
    }
    return out.toOwnedSlice(arena);
}

pub fn upperCamel(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var uppercase_next = true;
    for (input) |ch| {
        if (!(std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch))) {
            uppercase_next = true;
            continue;
        }

        if (uppercase_next) {
            try out.append(allocator, std.ascii.toUpper(ch));
        } else {
            try out.append(allocator, ch);
        }
        uppercase_next = false;
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "Event");
    }

    return out.toOwnedSlice(allocator);
}

/// Returns true if the type is a scalar that can use the existing
/// method codegen paths directly.
pub fn isScalarType(value: api.ApiType) bool {
    return switch (value) {
        .string, .int, .bool, .void => true,
        .user_struct, .user_enum => false,
    };
}

/// Maps high-level API type tags to C-ABI transport categories.
pub fn wireKind(value: api.ApiType) WireKind {
    return switch (value) {
        .string, .user_struct => .string,
        .int, .user_enum => .int,
        .bool => .bool,
        .void => .void,
    };
}
