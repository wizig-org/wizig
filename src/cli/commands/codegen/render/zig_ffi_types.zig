//! Zig type alias generation for user-defined structs and enums in FFI root.

const std = @import("std");
const api = @import("../model/api.zig");
const helpers = @import("helpers.zig");

pub fn appendUserTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
    if (structs.len == 0 and enums.len == 0) return;

    try out.appendSlice(arena, "// User-defined type aliases (resolved from app module)\n");

    for (enums) |e| {
        try helpers.appendFmt(out, arena, "const {s} = app.{s};\n", .{ e.name, e.name });
    }

    for (structs) |s| {
        try helpers.appendFmt(out, arena, "const {s} = app.{s};\n", .{ s.name, s.name });
    }

    try out.appendSlice(arena, "\n");
}

test "appendUserTypeDefinitions emits aliases" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var out = std.ArrayList(u8).empty;
    const structs = [_]api.UserStruct{
        .{ .name = "UserProfile", .fields = &.{
            .{ .name = "name", .field_type = .string },
            .{ .name = "age", .field_type = .int },
        } },
    };
    const enums = [_]api.UserEnum{
        .{ .name = "Color", .variants = &.{ "red", "green", "blue" } },
    };

    try appendUserTypeDefinitions(&out, arena, &structs, &enums);
    const result = out.items;

    try std.testing.expect(std.mem.indexOf(u8, result, "const Color = app.Color;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "const UserProfile = app.UserProfile;") != null);
}
