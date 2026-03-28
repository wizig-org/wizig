//! Equality helpers for API spec merge validation.
const std = @import("std");

const api = @import("../../model/api.zig");

/// Returns whether two API type descriptors are structurally equal.
pub fn apiTypesEqual(lhs: api.ApiType, rhs: api.ApiType) bool {
    return switch (lhs) {
        .string => switch (rhs) {
            .string => true,
            else => false,
        },
        .int => switch (rhs) {
            .int => true,
            else => false,
        },
        .bool => switch (rhs) {
            .bool => true,
            else => false,
        },
        .void => switch (rhs) {
            .void => true,
            else => false,
        },
        .user_struct => |lhs_name| switch (rhs) {
            .user_struct => |rhs_name| std.mem.eql(u8, lhs_name, rhs_name),
            else => false,
        },
        .user_enum => |lhs_name| switch (rhs) {
            .user_enum => |rhs_name| std.mem.eql(u8, lhs_name, rhs_name),
            else => false,
        },
    };
}

/// Returns whether two user struct definitions are structurally equal.
pub fn structsEqual(lhs: api.UserStruct, rhs: api.UserStruct) bool {
    if (lhs.fields.len != rhs.fields.len) return false;
    for (lhs.fields, rhs.fields) |lhs_field, rhs_field| {
        if (!std.mem.eql(u8, lhs_field.name, rhs_field.name)) return false;
        if (!apiTypesEqual(lhs_field.field_type, rhs_field.field_type)) return false;
    }
    return true;
}

/// Returns whether two user enum definitions are structurally equal.
pub fn enumsEqual(lhs: api.UserEnum, rhs: api.UserEnum) bool {
    if (lhs.variants.len != rhs.variants.len) return false;
    for (lhs.variants, rhs.variants) |lhs_variant, rhs_variant| {
        if (!std.mem.eql(u8, lhs_variant, rhs_variant)) return false;
    }
    return true;
}

test "apiTypesEqual compares primitives and named types" {
    try std.testing.expect(apiTypesEqual(.string, .string));
    try std.testing.expect(apiTypesEqual(.{ .user_struct = "User" }, .{ .user_struct = "User" }));
    try std.testing.expect(!apiTypesEqual(.int, .bool));
}
