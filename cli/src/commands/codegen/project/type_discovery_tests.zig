//! Unit tests for project user-type discovery.
//!
//! These tests focus on parser correctness and type-token resolution behavior
//! independent from filesystem walking.

const std = @import("std");
const type_discovery = @import("type_discovery.zig");

test "parseStructsFromSource resolves primitive and discovered user types" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const source =
        \\pub const Color = enum {
        \\    red,
        \\    green,
        \\};
        \\
        \\pub const UserProfile = struct {
        \\    name: []const u8,
        \\    favorite: Color,
        \\};
    ;

    const structs = try type_discovery.parseStructsFromSource(arena, source);
    try std.testing.expectEqual(@as(usize, 1), structs.len);
    try std.testing.expectEqualStrings("UserProfile", structs[0].name);
    try std.testing.expectEqual(@as(usize, 2), structs[0].fields.len);
    try std.testing.expect(structs[0].fields[0].field_type == .string);
    switch (structs[0].fields[1].field_type) {
        .user_enum => |name| try std.testing.expectEqualStrings("Color", name),
        else => return error.TestUnexpectedResult,
    }
}

test "parseEnumsFromSource parses variants with explicit ordinals" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const source =
        \\pub const Status = enum(i64) {
        \\    active = 0,
        \\    inactive = 1,
        \\};
    ;

    const enums = try type_discovery.parseEnumsFromSource(arena, source);
    try std.testing.expectEqual(@as(usize, 1), enums.len);
    try std.testing.expectEqualStrings("Status", enums[0].name);
    try std.testing.expectEqual(@as(usize, 2), enums[0].variants.len);
    try std.testing.expectEqualStrings("active", enums[0].variants[0]);
    try std.testing.expectEqualStrings("inactive", enums[0].variants[1]);
}

test "parseFieldType resolves known discovered struct and enum names" {
    const struct_names = [_][]const u8{"UserProfile"};
    const enum_names = [_][]const u8{"Color"};

    const struct_type = type_discovery.parseFieldType("UserProfile", &struct_names, &enum_names) orelse return error.TestUnexpectedResult;
    const enum_type = type_discovery.parseFieldType("Color", &struct_names, &enum_names) orelse return error.TestUnexpectedResult;

    switch (struct_type) {
        .user_struct => |name| try std.testing.expectEqualStrings("UserProfile", name),
        else => return error.TestUnexpectedResult,
    }
    switch (enum_type) {
        .user_enum => |name| try std.testing.expectEqualStrings("Color", name),
        else => return error.TestUnexpectedResult,
    }

    const int_type = type_discovery.parseFieldType("i64", &struct_names, &enum_names) orelse return error.TestUnexpectedResult;
    const str_type = type_discovery.parseFieldType("[]const u8", &struct_names, &enum_names) orelse return error.TestUnexpectedResult;
    try std.testing.expect(switch (int_type) {
        .int => true,
        else => false,
    });
    try std.testing.expect(switch (str_type) {
        .string => true,
        else => false,
    });
}
