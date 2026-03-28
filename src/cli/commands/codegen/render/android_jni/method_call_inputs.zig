const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");
const method_call_returns = @import("method_call_returns.zig");

pub fn appendMethodBody(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
    method: api.ApiMethod,
) !void {
    const output_wire = helpers.wireKind(method.output);
    const is_struct_output = method.output == .user_struct;

    if (is_struct_output or output_wire == .string) {
        try out.appendSlice(arena, "    uint8_t* out_ptr = NULL;\n");
        try out.appendSlice(arena, "    size_t out_len = 0;\n");
    } else if (output_wire == .int) {
        try out.appendSlice(arena, "    int64_t out_value = 0;\n");
    } else if (output_wire == .bool) {
        try out.appendSlice(arena, "    uint8_t out_value = 0;\n");
    }

    try appendInputAndCall(out, arena, ffi_name, method);

    if (is_struct_output or output_wire == .string) {
        try method_call_returns.appendByteOutputReturn(out, arena, ffi_name, is_struct_output);
    } else if (output_wire == .int) {
        try method_call_returns.appendIntOutputReturn(out, arena, ffi_name);
    } else if (output_wire == .bool) {
        try method_call_returns.appendBoolOutputReturn(out, arena, ffi_name);
    } else {
        try method_call_returns.appendVoidOutputReturn(out, arena, ffi_name);
    }
}

fn appendInputAndCall(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
    method: api.ApiMethod,
) !void {
    const output_wire = helpers.wireKind(method.output);
    const is_struct_output = method.output == .user_struct;
    const null_ret = method_call_returns.nullReturnForOutput(output_wire);

    switch (method.input) {
        .void => try appendFfiCall(out, arena, ffi_name, null, output_wire, is_struct_output),
        .user_struct => try appendByteArrayInput(out, arena, ffi_name, null_ret, output_wire, is_struct_output),
        .string => try appendStringInput(out, arena, ffi_name, null_ret, output_wire, is_struct_output),
        .int, .user_enum => try appendFfiCall(out, arena, ffi_name, "(int64_t)input", output_wire, is_struct_output),
        .bool => try appendFfiCall(out, arena, ffi_name, "input ? 1 : 0", output_wire, is_struct_output),
    }
}

fn appendByteArrayInput(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
    null_ret: []const u8,
    output_wire: helpers.WireKind,
    is_struct_output: bool,
) !void {
    try out.appendSlice(arena, "    if (input == NULL) {\n");
    try helpers.appendFmt(out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
    try helpers.appendFmt(out, arena, "        return {s};\n", .{null_ret});
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    jsize input_len = (*env)->GetArrayLength(env, input);\n");
    try out.appendSlice(arena, "    jbyte* input_bytes = (*env)->GetByteArrayElements(env, input, NULL);\n");
    try helpers.appendFmt(out, arena, "    if (input_bytes == NULL) return {s};\n", .{null_ret});
    try appendFfiCall(out, arena, ffi_name, "(const uint8_t*)input_bytes, (size_t)input_len", output_wire, is_struct_output);
    try out.appendSlice(arena, "    (*env)->ReleaseByteArrayElements(env, input, input_bytes, JNI_ABORT);\n");
}

fn appendStringInput(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
    null_ret: []const u8,
    output_wire: helpers.WireKind,
    is_struct_output: bool,
) !void {
    try out.appendSlice(arena, "    if (input == NULL) {\n");
    try helpers.appendFmt(out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
    try helpers.appendFmt(out, arena, "        return {s};\n", .{null_ret});
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    jsize input_len = (*env)->GetStringUTFLength(env, input);\n");
    try out.appendSlice(arena, "    const char* input_utf = (*env)->GetStringUTFChars(env, input, NULL);\n");
    try helpers.appendFmt(out, arena, "    if (input_utf == NULL) return {s};\n", .{null_ret});
    try appendFfiCall(out, arena, ffi_name, "(const uint8_t*)input_utf, (size_t)input_len", output_wire, is_struct_output);
    try out.appendSlice(arena, "    (*env)->ReleaseStringUTFChars(env, input, input_utf);\n");
}

fn appendFfiCall(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
    input_expr: ?[]const u8,
    output_wire: helpers.WireKind,
    is_struct_output: bool,
) !void {
    const out_args = if (is_struct_output or output_wire == .string)
        "&out_ptr, &out_len"
    else if (output_wire == .int or output_wire == .bool)
        "&out_value"
    else
        "";

    if (input_expr) |expr| {
        if (out_args.len > 0) {
            try helpers.appendFmt(out, arena, "    int32_t status = {s}({s}, {s});\n", .{ ffi_name, expr, out_args });
        } else {
            try helpers.appendFmt(out, arena, "    int32_t status = {s}({s});\n", .{ ffi_name, expr });
        }
    } else if (out_args.len > 0) {
        try helpers.appendFmt(out, arena, "    int32_t status = {s}({s});\n", .{ ffi_name, out_args });
    } else {
        try helpers.appendFmt(out, arena, "    int32_t status = {s}();\n", .{ffi_name});
    }
}
