//! Swift type definition generation for user-defined structs and enums.

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

pub fn appendSwiftTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
    for (enums) |e| {
        try helpers.appendFmt(out, arena, "public enum {s}: Int64, CaseIterable, Codable {{\n", .{e.name});
        for (e.variants, 0..) |variant, i| {
            try helpers.appendFmt(out, arena, "    case {s} = {d}\n", .{ variant, i });
        }
        try out.appendSlice(arena, "}\n\n");
    }

    for (structs) |s| {
        try helpers.appendFmt(out, arena, "public struct {s}: Codable {{\n", .{s.name});
        for (s.fields) |field| {
            try helpers.appendFmt(out, arena, "    public var {s}: {s}\n", .{ field.name, helpers.swiftType(field.field_type) });
        }
        try out.appendSlice(arena, "}\n\n");
    }
}

test "appendSwiftTypeDefinitions emits Codable structs and enums" {
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

    try appendSwiftTypeDefinitions(&out, arena, &structs, &enums);
    const result = out.items;

    try std.testing.expect(std.mem.indexOf(u8, result, "public enum Color: Int64, CaseIterable, Codable") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "case red = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "case blue = 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "public struct UserProfile: Codable") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "public var name: String") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "public var age: Int64") != null);
}
