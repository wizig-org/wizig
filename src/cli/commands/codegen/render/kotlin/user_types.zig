//! Kotlin type definition generation for user structs and enums.
//!
//! To keep Android integration dependency-free, struct JSON conversion is
//! generated with `org.json.JSONObject` helpers instead of external serializers.

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

/// Appends Kotlin enum/data classes plus JSON helpers for user types.
pub fn appendKotlinTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
    for (enums) |e| {
        try helpers.appendFmt(out, arena, "enum class {s}(val rawValue: Long) {{\n", .{e.name});
        for (e.variants, 0..) |variant, index| {
            const suffix = if (index + 1 == e.variants.len) ";" else ",";
            try helpers.appendFmt(out, arena, "    {s}({d}){s}\n", .{ variant, index, suffix });
        }
        try helpers.appendFmt(
            out,
            arena,
            "    companion object {{\n" ++
                "        fun fromRaw(rawValue: Long): {s} =\n" ++
                "            entries.firstOrNull {{ it.rawValue == rawValue }}\n" ++
                "                ?: throw IllegalArgumentException(\"Unknown {s} raw value: $rawValue\")\n" ++
                "    }}\n",
            .{ e.name, e.name },
        );
        try out.appendSlice(arena, "}\n\n");
    }

    for (structs) |s| {
        try helpers.appendFmt(out, arena, "data class {s}(\n", .{s.name});
        for (s.fields, 0..) |field, index| {
            const suffix = if (index + 1 == s.fields.len) "" else ",";
            try helpers.appendFmt(out, arena, "    val {s}: {s}{s}\n", .{ field.name, helpers.kotlinType(field.field_type), suffix });
        }
        try out.appendSlice(arena, ") {\n");

        try out.appendSlice(arena, "    fun toJson(): String {\n");
        try out.appendSlice(arena, "        val obj = org.json.JSONObject()\n");
        for (s.fields) |field| {
            try appendStructToJsonLine(out, arena, field);
        }
        try out.appendSlice(arena, "        return obj.toString()\n");
        try out.appendSlice(arena, "    }\n\n");

        try helpers.appendFmt(out, arena, "    companion object {{\n        fun fromJson(json: String): {s} {{\n", .{s.name});
        try out.appendSlice(arena, "            val obj = org.json.JSONObject(json)\n");
        try helpers.appendFmt(out, arena, "            return {s}(\n", .{s.name});
        for (s.fields, 0..) |field, index| {
            const suffix = if (index + 1 == s.fields.len) "" else ",";
            try appendStructFromJsonLine(out, arena, field, suffix);
        }
        try out.appendSlice(arena, "            )\n");
        try out.appendSlice(arena, "        }\n");
        try out.appendSlice(arena, "    }\n");
        try out.appendSlice(arena, "}\n\n");
    }
}

fn appendStructToJsonLine(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    field: api.StructField,
) !void {
    switch (field.field_type) {
        .string, .int, .bool => {
            try helpers.appendFmt(out, arena, "        obj.put(\"{s}\", {s})\n", .{ field.name, field.name });
        },
        .user_enum => {
            try helpers.appendFmt(out, arena, "        obj.put(\"{s}\", {s}.rawValue)\n", .{ field.name, field.name });
        },
        .user_struct => {
            try helpers.appendFmt(out, arena, "        obj.put(\"{s}\", org.json.JSONObject({s}.toJson()))\n", .{ field.name, field.name });
        },
        .void => {},
    }
}

fn appendStructFromJsonLine(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    field: api.StructField,
    suffix: []const u8,
) !void {
    switch (field.field_type) {
        .string => {
            try helpers.appendFmt(out, arena, "                {s} = obj.getString(\"{s}\"){s}\n", .{ field.name, field.name, suffix });
        },
        .int => {
            try helpers.appendFmt(out, arena, "                {s} = obj.getLong(\"{s}\"){s}\n", .{ field.name, field.name, suffix });
        },
        .bool => {
            try helpers.appendFmt(out, arena, "                {s} = obj.getBoolean(\"{s}\"){s}\n", .{ field.name, field.name, suffix });
        },
        .user_enum => |name| {
            try helpers.appendFmt(out, arena, "                {s} = {s}.fromRaw(obj.getLong(\"{s}\")){s}\n", .{ field.name, name, field.name, suffix });
        },
        .user_struct => |name| {
            try helpers.appendFmt(out, arena, "                {s} = {s}.fromJson(obj.getJSONObject(\"{s}\").toString()){s}\n", .{ field.name, name, field.name, suffix });
        },
        .void => {},
    }
}
