//! Kotlin type definition generation for user structs and enums.
//!
//! Struct serialization uses a compact binary wire format (v1) with
//! `ByteBuffer` / `ByteArrayOutputStream` instead of JSON, keeping the
//! Android integration dependency-free.

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

/// Appends Kotlin enum/data classes plus binary wire helpers for user types.
pub fn appendKotlinTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
    if (structs.len > 0) {
        try appendBinaryWireHelpers(out, arena);
    }

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
        try appendToBinaryMethod(out, arena, s);
        try appendFromBinaryCompanion(out, arena, s);
        try out.appendSlice(arena, "}\n\n");
    }
}

/// Emits private utility functions for binary wire encoding/decoding.
fn appendBinaryWireHelpers(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena,
        \\private fun writeLE32(out: java.io.ByteArrayOutputStream, v: Int) {
        \\    val buf = ByteArray(4)
        \\    java.nio.ByteBuffer.wrap(buf).order(java.nio.ByteOrder.LITTLE_ENDIAN).putInt(v)
        \\    out.write(buf)
        \\}
        \\
        \\private fun writeLE64(out: java.io.ByteArrayOutputStream, v: Long) {
        \\    val buf = ByteArray(8)
        \\    java.nio.ByteBuffer.wrap(buf).order(java.nio.ByteOrder.LITTLE_ENDIAN).putLong(v)
        \\    out.write(buf)
        \\}
        \\
        \\private fun readStringLE(buf: java.nio.ByteBuffer): String {
        \\    val len = buf.getInt()
        \\    val bytes = ByteArray(len)
        \\    buf.get(bytes)
        \\    return String(bytes, Charsets.UTF_8)
        \\}
        \\
        \\
    );
}

/// Emits the `toBinary()` method that serializes struct fields in contract order.
fn appendToBinaryMethod(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    s: api.UserStruct,
) !void {
    try out.appendSlice(arena, "    fun toBinary(): ByteArray {\n");
    try out.appendSlice(arena, "        val buf = java.io.ByteArrayOutputStream()\n");
    for (s.fields) |field| {
        try appendFieldToBinary(out, arena, field);
    }
    try out.appendSlice(arena, "        return buf.toByteArray()\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits `companion object` with `fromBinary` and `fromBinaryBuffer` decoders.
fn appendFromBinaryCompanion(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    s: api.UserStruct,
) !void {
    try helpers.appendFmt(out, arena,
        "    companion object {{\n" ++
            "        fun fromBinary(data: ByteArray): {s} {{\n" ++
            "            val buf = java.nio.ByteBuffer.wrap(data).order(java.nio.ByteOrder.LITTLE_ENDIAN)\n" ++
            "            return fromBinaryBuffer(buf)\n" ++
            "        }}\n\n" ++
            "        fun fromBinaryBuffer(buf: java.nio.ByteBuffer): {s} {{\n" ++
            "            return {s}(\n",
        .{ s.name, s.name, s.name },
    );
    for (s.fields, 0..) |field, index| {
        const suffix = if (index + 1 == s.fields.len) "" else ",";
        try appendFieldFromBinary(out, arena, field, suffix);
    }
    try out.appendSlice(arena, "            )\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n");
}

/// Emits one binary write statement for a struct field in `toBinary()`.
fn appendFieldToBinary(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    field: api.StructField,
) !void {
    switch (field.field_type) {
        .string => {
            try helpers.appendFmt(out, arena, "        val {s}Bytes = {s}.toByteArray(Charsets.UTF_8)\n", .{ field.name, field.name });
            try helpers.appendFmt(out, arena, "        writeLE32(buf, {s}Bytes.size)\n", .{field.name});
            try helpers.appendFmt(out, arena, "        buf.write({s}Bytes)\n", .{field.name});
        },
        .int => try helpers.appendFmt(out, arena, "        writeLE64(buf, {s})\n", .{field.name}),
        .bool => try helpers.appendFmt(out, arena, "        buf.write(if ({s}) 1 else 0)\n", .{field.name}),
        .user_enum => try helpers.appendFmt(out, arena, "        writeLE64(buf, {s}.rawValue)\n", .{field.name}),
        .user_struct => try helpers.appendFmt(out, arena, "        buf.write({s}.toBinary())\n", .{field.name}),
        .void => {},
    }
}

/// Emits one binary read expression for a struct field in `fromBinaryBuffer()`.
fn appendFieldFromBinary(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    field: api.StructField,
    suffix: []const u8,
) !void {
    switch (field.field_type) {
        .string => try helpers.appendFmt(out, arena, "                {s} = readStringLE(buf){s}\n", .{ field.name, suffix }),
        .int => try helpers.appendFmt(out, arena, "                {s} = buf.getLong(){s}\n", .{ field.name, suffix }),
        .bool => try helpers.appendFmt(out, arena, "                {s} = buf.get().toInt() != 0{s}\n", .{ field.name, suffix }),
        .user_enum => |name| try helpers.appendFmt(out, arena, "                {s} = {s}.fromRaw(buf.getLong()){s}\n", .{ field.name, name, suffix }),
        .user_struct => |name| try helpers.appendFmt(out, arena, "                {s} = {s}.fromBinaryBuffer(buf){s}\n", .{ field.name, name, suffix }),
        .void => {},
    }
}
