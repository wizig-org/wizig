//! Swift type definition generation for user-defined structs and enums.
//!
//! Structs get `toBinary()` and `fromBinary`/`fromBinaryReader` methods for
//! wire format v1 encoding. Enums use `Int64` raw values (no Codable).

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

/// Appends Swift enum and struct definitions including binary wire methods.
pub fn appendSwiftTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
    for (enums) |e| {
        try helpers.appendFmt(out, arena, "public enum {s}: Int64, CaseIterable {{\n", .{e.name});
        for (e.variants, 0..) |variant, i| {
            try helpers.appendFmt(out, arena, "    case {s} = {d}\n", .{ variant, i });
        }
        try out.appendSlice(arena, "}\n\n");
    }

    for (structs) |s| {
        try appendStructDefinition(out, arena, s);
    }
}

/// Emits a single struct with properties, `toBinary`, `fromBinary`,
/// and `fromBinaryReader` methods.
fn appendStructDefinition(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    s: api.UserStruct,
) !void {
    try helpers.appendFmt(out, arena, "public struct {s} {{\n", .{s.name});
    for (s.fields) |field| {
        try helpers.appendFmt(out, arena, "    public var {s}: {s}\n", .{ field.name, helpers.swiftType(field.field_type) });
    }
    try out.appendSlice(arena, "\n");
    try appendToBinary(out, arena, s.fields);
    try appendFromBinary(out, arena, s.name, s.fields);
    try out.appendSlice(arena, "}\n\n");
}

/// Emits the `toBinary() -> [UInt8]` instance method.
fn appendToBinary(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    fields: []const api.StructField,
) !void {
    try out.appendSlice(arena, "    func toBinary() -> [UInt8] {\n");
    try out.appendSlice(arena, "        var w = WizigWireWriter()\n");
    for (fields) |field| {
        try appendWriteField(out, arena, field);
    }
    try out.appendSlice(arena, "        return w.bytes\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits a single field write call inside `toBinary`.
fn appendWriteField(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    field: api.StructField,
) !void {
    switch (field.field_type) {
        .string => try helpers.appendFmt(out, arena, "        w.writeString({s})\n", .{field.name}),
        .int => try helpers.appendFmt(out, arena, "        w.writeI64({s})\n", .{field.name}),
        .bool => try helpers.appendFmt(out, arena, "        w.writeBool({s})\n", .{field.name}),
        .user_enum => try helpers.appendFmt(out, arena, "        w.writeI64({s}.rawValue)\n", .{field.name}),
        .user_struct => try helpers.appendFmt(out, arena, "        w.bytes.append(contentsOf: {s}.toBinary())\n", .{field.name}),
        .void => {},
    }
}

/// Emits `fromBinary` and `fromBinaryReader` static methods.
fn appendFromBinary(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    name: []const u8,
    fields: []const api.StructField,
) !void {
    try helpers.appendFmt(out, arena, "    static func fromBinary(_ ptr: UnsafeRawPointer, _ len: Int) throws -> {s} {{\n", .{name});
    try out.appendSlice(arena, "        var r = WizigWireReader(ptr: ptr, len: len)\n");
    try helpers.appendFmt(out, arena, "        return try fromBinaryReader(&r)\n", .{});
    try out.appendSlice(arena, "    }\n\n");

    try helpers.appendFmt(out, arena, "    fileprivate static func fromBinaryReader(_ r: inout WizigWireReader) throws -> {s} {{\n", .{name});
    try helpers.appendFmt(out, arena, "        return try {s}(\n", .{name});
    for (fields, 0..) |field, i| {
        const comma: []const u8 = if (i + 1 < fields.len) "," else "";
        try appendReadField(out, arena, field, comma);
    }
    try out.appendSlice(arena, "        )\n");
    try out.appendSlice(arena, "    }\n");
}

/// Emits a single field read expression inside `fromBinaryReader`.
fn appendReadField(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    field: api.StructField,
    comma: []const u8,
) !void {
    switch (field.field_type) {
        .string => try helpers.appendFmt(out, arena, "            {s}: try r.readString(){s}\n", .{ field.name, comma }),
        .int => try helpers.appendFmt(out, arena, "            {s}: try r.readI64(){s}\n", .{ field.name, comma }),
        .bool => try helpers.appendFmt(out, arena, "            {s}: try r.readBool(){s}\n", .{ field.name, comma }),
        .user_enum => |enum_name| try helpers.appendFmt(
            out,
            arena,
            "            {s}: {{ let raw = try r.readI64(); guard let value = {s}(rawValue: raw) else {{ throw WizigGeneratedApiError.invalidEnumRawValue(function: \"wire\", rawValue: raw, typeName: \"{s}\") }}; return value }}(){s}\n",
            .{ field.name, enum_name, enum_name, comma },
        ),
        .user_struct => |struct_name| try helpers.appendFmt(out, arena, "            {s}: try {s}.fromBinaryReader(&r){s}\n", .{ field.name, struct_name, comma }),
        .void => {},
    }
}

test "appendSwiftTypeDefinitions emits structs with binary wire methods" {
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

    try std.testing.expect(std.mem.indexOf(u8, result, "public enum Color: Int64, CaseIterable") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "case red = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "case blue = 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "public struct UserProfile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Codable") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "public var name: String") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "public var age: Int64") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "func toBinary()") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "static func fromBinary(") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "w.writeString(name)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "w.writeI64(age)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "r.readString()") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "r.readI64()") != null);
}
