//! Unit tests for contract parsing from Zig and JSON sources.

const std = @import("std");
const parse = @import("parse.zig");

test "parseApiSpecFromZig parses structs/enums and resolves method user types" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const text =
        \\pub const namespace = "dev.wizig.example";
        \\pub const methods = .{
        \\    .{ .name = "save_profile", .input = .UserProfile, .output = .void },
        \\    .{ .name = "favorite_color", .input = .void, .output = .Color },
        \\};
        \\pub const events = .{
        \\    .{ .name = "profile_saved", .payload = .UserProfile },
        \\};
        \\pub const structs = .{
        \\    .{
        \\        .name = "UserProfile",
        \\        .fields = .{
        \\            .{ .name = "name", .field_type = .string },
        \\            .{ .name = "favorite", .field_type = .Color },
        \\        },
        \\    },
        \\};
        \\pub const enums = .{
        \\    .{
        \\        .name = "Color",
        \\        .variants = .{
        \\            "red",
        \\            "green",
        \\        },
        \\    },
        \\};
    ;

    const spec = try parse.parseApiSpecFromZig(arena, text);
    try std.testing.expectEqualStrings("dev.wizig.example", spec.namespace);
    try std.testing.expectEqual(@as(usize, 2), spec.methods.len);
    try std.testing.expectEqual(@as(usize, 1), spec.structs.len);
    try std.testing.expectEqual(@as(usize, 1), spec.enums.len);

    switch (spec.methods[0].input) {
        .user_struct => |name| try std.testing.expectEqualStrings("UserProfile", name),
        else => return error.TestUnexpectedResult,
    }
    switch (spec.methods[1].output) {
        .user_enum => |name| try std.testing.expectEqualStrings("Color", name),
        else => return error.TestUnexpectedResult,
    }
    switch (spec.structs[0].fields[1].field_type) {
        .user_enum => |name| try std.testing.expectEqualStrings("Color", name),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("green", spec.enums[0].variants[1]);
}

test "parseApiSpecFromJson parses structs/enums and resolves method user types" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const text =
        \\{
        \\  "namespace": "dev.wizig.example",
        \\  "methods": [
        \\    { "name": "save_profile", "input": "UserProfile", "output": "void" },
        \\    { "name": "favorite_color", "input": "void", "output": "Color" }
        \\  ],
        \\  "events": [
        \\    { "name": "profile_saved", "payload": "UserProfile" }
        \\  ],
        \\  "structs": [
        \\    {
        \\      "name": "UserProfile",
        \\      "fields": [
        \\        { "name": "name", "field_type": "string" },
        \\        { "name": "favorite", "field_type": "Color" }
        \\      ]
        \\    }
        \\  ],
        \\  "enums": [
        \\    {
        \\      "name": "Color",
        \\      "variants": ["red", "green"]
        \\    }
        \\  ]
        \\}
    ;

    const spec = try parse.parseApiSpecFromJson(arena, text);
    try std.testing.expectEqualStrings("dev.wizig.example", spec.namespace);
    try std.testing.expectEqual(@as(usize, 2), spec.methods.len);
    try std.testing.expectEqual(@as(usize, 1), spec.structs.len);
    try std.testing.expectEqual(@as(usize, 1), spec.enums.len);

    switch (spec.methods[0].input) {
        .user_struct => |name| try std.testing.expectEqualStrings("UserProfile", name),
        else => return error.TestUnexpectedResult,
    }
    switch (spec.methods[1].output) {
        .user_enum => |name| try std.testing.expectEqualStrings("Color", name),
        else => return error.TestUnexpectedResult,
    }
}
