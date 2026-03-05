//! Unit tests for API spec merge behavior.

const std = @import("std");
const api = @import("../model/api.zig");
const spec = @import("spec.zig");

test "mergeSpecWithDiscoveredTypes merges discovered structs and enums" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const base_spec: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .structs = &.{},
        .enums = &.{},
    };

    const discovered_methods = [_]api.ApiMethod{
        .{ .name = "favorite_color", .input = .void, .output = .{ .user_enum = "Color" } },
    };
    const discovered_structs = [_]api.UserStruct{
        .{ .name = "UserProfile", .fields = &.{
            .{ .name = "name", .field_type = .string },
            .{ .name = "favorite", .field_type = .{ .user_enum = "Color" } },
        } },
    };
    const discovered_enums = [_]api.UserEnum{
        .{ .name = "Color", .variants = &.{ "red", "green" } },
    };

    const merged = try spec.mergeSpecWithDiscoveredTypes(
        arena,
        base_spec,
        &discovered_methods,
        &discovered_structs,
        &discovered_enums,
    );

    try std.testing.expectEqual(@as(usize, 1), merged.methods.len);
    try std.testing.expectEqual(@as(usize, 1), merged.structs.len);
    try std.testing.expectEqual(@as(usize, 1), merged.enums.len);
}

test "mergeSpecWithDiscoveredTypes rejects conflicting struct definitions" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const base_spec: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .structs = &.{.{ .name = "UserProfile", .fields = &.{
            .{ .name = "name", .field_type = .string },
        } }},
        .enums = &.{},
    };
    const discovered_structs = [_]api.UserStruct{
        .{ .name = "UserProfile", .fields = &.{
            .{ .name = "name", .field_type = .string },
            .{ .name = "age", .field_type = .int },
        } },
    };

    try std.testing.expectError(
        error.InvalidContract,
        spec.mergeSpecWithDiscoveredTypes(arena, base_spec, &.{}, &discovered_structs, &.{}),
    );
}
