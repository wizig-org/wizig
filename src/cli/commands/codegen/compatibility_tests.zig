const std = @import("std");
const api = @import("model/api.zig");
const compatibility = @import("compatibility.zig");

test "computeContractHashHex is stable for identical inputs" {
    const spec: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{
            .{ .name = "echo", .input = .string, .output = .string },
            .{ .name = "uptime", .input = .void, .output = .int },
        },
        .events = &.{.{ .name = "log", .payload = .string }},
    };

    const first = try compatibility.computeContractHashHex(std.testing.allocator, spec);
    defer std.testing.allocator.free(first);
    const second = try compatibility.computeContractHashHex(std.testing.allocator, spec);
    defer std.testing.allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
}

test "computeContractHashHex changes when method signature changes" {
    const spec_a: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{.{ .name = "echo", .input = .string, .output = .string }},
        .events = &.{.{ .name = "log", .payload = .string }},
    };
    const spec_b: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{.{ .name = "echo", .input = .string, .output = .int }},
        .events = &.{.{ .name = "log", .payload = .string }},
    };

    const first = try compatibility.computeContractHashHex(std.testing.allocator, spec_a);
    defer std.testing.allocator.free(first);
    const second = try compatibility.computeContractHashHex(std.testing.allocator, spec_b);
    defer std.testing.allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "computeContractHashHex changes when struct fields change" {
    const spec_a: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .structs = &.{.{ .name = "Profile", .fields = &.{.{ .name = "name", .field_type = .string }} }},
    };
    const spec_b: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .structs = &.{.{ .name = "Profile", .fields = &.{
            .{ .name = "name", .field_type = .string },
            .{ .name = "age", .field_type = .int },
        } }},
    };

    const first = try compatibility.computeContractHashHex(std.testing.allocator, spec_a);
    defer std.testing.allocator.free(first);
    const second = try compatibility.computeContractHashHex(std.testing.allocator, spec_b);
    defer std.testing.allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "computeContractHashHex changes when enum variants change" {
    const spec_a: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .enums = &.{.{ .name = "Color", .variants = &.{ "red", "green" } }},
    };
    const spec_b: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{},
        .events = &.{},
        .enums = &.{.{ .name = "Color", .variants = &.{ "red", "green", "blue" } }},
    };

    const first = try compatibility.computeContractHashHex(std.testing.allocator, spec_a);
    defer std.testing.allocator.free(first);
    const second = try compatibility.computeContractHashHex(std.testing.allocator, spec_b);
    defer std.testing.allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "computeContractHashHex changes when user payload names change" {
    const spec_a: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{.{ .name = "save", .input = .{ .user_struct = "ProfileA" }, .output = .void }},
        .events = &.{},
    };
    const spec_b: api.ApiSpec = .{
        .namespace = "dev.wizig.app",
        .methods = &.{.{ .name = "save", .input = .{ .user_struct = "ProfileB" }, .output = .void }},
        .events = &.{},
    };

    const first = try compatibility.computeContractHashHex(std.testing.allocator, spec_a);
    defer std.testing.allocator.free(first);
    const second = try compatibility.computeContractHashHex(std.testing.allocator, spec_b);
    defer std.testing.allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}
