const std = @import("std");
const helpers = @import("../helpers.zig");

pub fn appendByteOutputReturn(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
    is_struct_output: bool,
) !void {
    try out.appendSlice(arena, "    if (status != 0) {\n");
    try helpers.appendFmt(out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
    try out.appendSlice(arena, "        if (out_ptr != NULL) wizig_bytes_free(out_ptr, out_len);\n");
    try out.appendSlice(arena, "        return NULL;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    if (out_ptr == NULL) {\n");
    try helpers.appendFmt(out, arena, "        throw_structured_error(env, \"wizig.runtime\", 255, \"{s} returned null output\");\n", .{ffi_name});
    try out.appendSlice(arena, "        return NULL;\n");
    try out.appendSlice(arena, "    }\n");

    if (is_struct_output) {
        try out.appendSlice(arena, "    jbyteArray result = (*env)->NewByteArray(env, (jsize)out_len);\n");
        try out.appendSlice(arena, "    if (result != NULL && out_len > 0) {\n");
        try out.appendSlice(arena, "        (*env)->SetByteArrayRegion(env, result, 0, (jsize)out_len, (const jbyte*)out_ptr);\n");
        try out.appendSlice(arena, "    }\n");
    } else {
        try out.appendSlice(arena, "    jstring result = new_jstring_from_bytes(env, out_ptr, out_len);\n");
    }
    try out.appendSlice(arena, "    wizig_bytes_free(out_ptr, out_len);\n");
    try out.appendSlice(arena, "    return result;\n");
}

pub fn appendIntOutputReturn(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
) !void {
    try out.appendSlice(arena, "    if (status != 0) {\n");
    try helpers.appendFmt(out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
    try out.appendSlice(arena, "        return 0;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    return (jlong)out_value;\n");
}

pub fn appendBoolOutputReturn(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
) !void {
    try out.appendSlice(arena, "    if (status != 0) {\n");
    try helpers.appendFmt(out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
    try out.appendSlice(arena, "        return JNI_FALSE;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    return out_value ? JNI_TRUE : JNI_FALSE;\n");
}

pub fn appendVoidOutputReturn(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
) !void {
    try out.appendSlice(arena, "    if (status != 0) {\n");
    try helpers.appendFmt(out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
    try out.appendSlice(arena, "    }\n");
}

pub fn nullReturnForOutput(output_wire: helpers.WireKind) []const u8 {
    return switch (output_wire) {
        .string => "NULL",
        .int => "0",
        .bool => "JNI_FALSE",
        .void => "",
    };
}
