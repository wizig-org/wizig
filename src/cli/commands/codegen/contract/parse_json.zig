//! JSON contract parser (`wizig.api.json`).

const std = @import("std");
const api = @import("../model/api.zig");
const shared = @import("parse_shared.zig");

/// Parses JSON contract text into an `ApiSpec`.
///
/// Expected schema:
/// - `namespace`: string
/// - `methods`: array of `{ name, input, output }`
/// - `events`: array of `{ name, payload }`
/// - `structs` (optional): array of `{ name, fields: [{ name, field_type }] }`
/// - `enums` (optional): array of `{ name, variants: [string] }`
pub fn parseApiSpecFromJson(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
    const parsed = try std.json.parseFromSlice(std.json.Value, arena, text, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidContract;
    const root = parsed.value.object;

    const namespace = try shared.dupRequiredString(arena, root, "namespace");
    const structs_value = root.get("structs");
    const enums_value = root.get("enums");

    const known_struct_names = try parseStructNames(arena, structs_value);
    const known_enum_names = try parseEnumNames(arena, enums_value);

    const methods = try parseMethods(arena, root, known_struct_names, known_enum_names);
    const events = try parseEvents(arena, root, known_struct_names, known_enum_names);
    const structs = try parseStructs(arena, structs_value, known_struct_names, known_enum_names);
    const enums = try parseEnums(arena, enums_value);

    return .{
        .namespace = namespace,
        .methods = methods,
        .events = events,
        .structs = structs,
        .enums = enums,
    };
}

fn parseStructNames(arena: std.mem.Allocator, value: ?std.json.Value) ![]const []const u8 {
    if (value == null) return &.{};
    if (value.? != .array) return error.InvalidContract;

    var names = std.ArrayList([]const u8).empty;
    for (value.?.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        try names.append(arena, try shared.dupRequiredString(arena, item.object, "name"));
    }
    return names.toOwnedSlice(arena);
}

fn parseEnumNames(arena: std.mem.Allocator, value: ?std.json.Value) ![]const []const u8 {
    if (value == null) return &.{};
    if (value.? != .array) return error.InvalidContract;

    var names = std.ArrayList([]const u8).empty;
    for (value.?.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        try names.append(arena, try shared.dupRequiredString(arena, item.object, "name"));
    }
    return names.toOwnedSlice(arena);
}

fn parseMethods(
    arena: std.mem.Allocator,
    root: std.json.ObjectMap,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.ApiMethod {
    const methods_value = root.get("methods") orelse return error.InvalidContract;
    if (methods_value != .array) return error.InvalidContract;

    var methods = std.ArrayList(api.ApiMethod).empty;
    for (methods_value.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        const obj = item.object;

        const name = try shared.dupRequiredString(arena, obj, "name");
        const input = try parseTypeField(obj, "input", known_struct_names, known_enum_names);
        const output = try parseTypeField(obj, "output", known_struct_names, known_enum_names);
        try methods.append(arena, .{
            .name = name,
            .input = input,
            .output = output,
        });
    }
    return methods.toOwnedSlice(arena);
}

fn parseEvents(
    arena: std.mem.Allocator,
    root: std.json.ObjectMap,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.ApiEvent {
    const events_value = root.get("events") orelse return error.InvalidContract;
    if (events_value != .array) return error.InvalidContract;

    var events = std.ArrayList(api.ApiEvent).empty;
    for (events_value.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        const obj = item.object;

        const name = try shared.dupRequiredString(arena, obj, "name");
        const payload = try parseTypeField(obj, "payload", known_struct_names, known_enum_names);
        try events.append(arena, .{
            .name = name,
            .payload = payload,
        });
    }
    return events.toOwnedSlice(arena);
}

fn parseStructs(
    arena: std.mem.Allocator,
    value: ?std.json.Value,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.UserStruct {
    if (value == null) return &.{};
    if (value.? != .array) return error.InvalidContract;

    var structs = std.ArrayList(api.UserStruct).empty;
    for (value.?.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        const obj = item.object;

        const name = try shared.dupRequiredString(arena, obj, "name");
        const fields_value = obj.get("fields") orelse return error.InvalidContract;
        if (fields_value != .array) return error.InvalidContract;

        var fields = std.ArrayList(api.StructField).empty;
        for (fields_value.array.items) |field_item| {
            if (field_item != .object) return error.InvalidContract;
            const field_obj = field_item.object;

            const field_name = try shared.dupRequiredString(arena, field_obj, "name");
            const field_type = try parseTypeField(field_obj, "field_type", known_struct_names, known_enum_names);
            try fields.append(arena, .{
                .name = field_name,
                .field_type = field_type,
            });
        }

        try structs.append(arena, .{
            .name = name,
            .fields = try fields.toOwnedSlice(arena),
        });
    }
    return structs.toOwnedSlice(arena);
}

fn parseEnums(arena: std.mem.Allocator, value: ?std.json.Value) ![]const api.UserEnum {
    if (value == null) return &.{};
    if (value.? != .array) return error.InvalidContract;

    var enums = std.ArrayList(api.UserEnum).empty;
    for (value.?.array.items) |item| {
        if (item != .object) return error.InvalidContract;
        const obj = item.object;

        const name = try shared.dupRequiredString(arena, obj, "name");
        const variants_value = obj.get("variants") orelse return error.InvalidContract;
        if (variants_value != .array) return error.InvalidContract;

        var variants = std.ArrayList([]const u8).empty;
        for (variants_value.array.items) |variant_item| {
            if (variant_item != .string or variant_item.string.len == 0) return error.InvalidContract;
            try variants.append(arena, try arena.dupe(u8, variant_item.string));
        }

        try enums.append(arena, .{
            .name = name,
            .variants = try variants.toOwnedSlice(arena),
        });
    }
    return enums.toOwnedSlice(arena);
}

fn parseTypeField(
    object: std.json.ObjectMap,
    field: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) !api.ApiType {
    const value = object.get(field) orelse return error.InvalidContract;
    if (value != .string) return error.InvalidContract;
    return shared.parseTypeTokenWithKnown(value.string, known_struct_names, known_enum_names);
}
