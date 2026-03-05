//! Per-method Android JNI export generation.

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

pub fn appendMethodExports(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
    for (methods) |method| {
        const ffi_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});
        const jni_name = try helpers.jniEscape(arena, ffi_name);
        const input_wire = helpers.wireKind(method.input);
        const output_wire = helpers.wireKind(method.output);
        try helpers.appendFmt(
            out,
            arena,
            "JNIEXPORT {s} JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_{s}(JNIEnv* env, jclass clazz",
            .{ helpers.jniCType(method.output), jni_name },
        );

        switch (input_wire) {
            .void => {},
            .string => try out.appendSlice(arena, ", jstring input"),
            .int => try out.appendSlice(arena, ", jlong input"),
            .bool => try out.appendSlice(arena, ", jboolean input"),
        }
        try out.appendSlice(arena, ") {\n");
        try out.appendSlice(arena, "    (void)clazz;\n");

        switch (output_wire) {
            .string => {
                try out.appendSlice(arena, "    uint8_t* out_ptr = NULL;\n");
                try out.appendSlice(arena, "    size_t out_len = 0;\n");
                switch (input_wire) {
                    .void => try helpers.appendFmt(out, arena, "    int32_t status = {s}(&out_ptr, &out_len);\n", .{ffi_name}),
                    .string => {
                        try out.appendSlice(arena, "    if (input == NULL) {\n");
                        try helpers.appendFmt(out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
                        try out.appendSlice(arena, "        return NULL;\n");
                        try out.appendSlice(arena, "    }\n");
                        try out.appendSlice(arena, "    const char* input_utf = (*env)->GetStringUTFChars(env, input, NULL);\n");
                        try out.appendSlice(arena, "    if (input_utf == NULL) return NULL;\n");
                        try helpers.appendFmt(out, arena, "    int32_t status = {s}((const uint8_t*)input_utf, strlen(input_utf), &out_ptr, &out_len);\n", .{ffi_name});
                        try out.appendSlice(arena, "    (*env)->ReleaseStringUTFChars(env, input, input_utf);\n");
                    },
                    .int => try helpers.appendFmt(out, arena, "    int32_t status = {s}((int64_t)input, &out_ptr, &out_len);\n", .{ffi_name}),
                    .bool => try helpers.appendFmt(out, arena, "    int32_t status = {s}(input ? 1 : 0, &out_ptr, &out_len);\n", .{ffi_name}),
                }
                try out.appendSlice(arena, "    if (status != 0) {\n");
                try helpers.appendFmt(out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
                try out.appendSlice(arena, "        if (out_ptr != NULL) wizig_bytes_free(out_ptr, out_len);\n");
                try out.appendSlice(arena, "        return NULL;\n");
                try out.appendSlice(arena, "    }\n");
                try out.appendSlice(arena, "    if (out_ptr == NULL) {\n");
                try helpers.appendFmt(out, arena, "        throw_structured_error(env, \"wizig.runtime\", 255, \"{s} returned null output\");\n", .{ffi_name});
                try out.appendSlice(arena, "        return NULL;\n");
                try out.appendSlice(arena, "    }\n");
                try out.appendSlice(arena, "    jstring result = new_jstring_from_bytes(env, out_ptr, out_len);\n");
                try out.appendSlice(arena, "    wizig_bytes_free(out_ptr, out_len);\n");
                try out.appendSlice(arena, "    return result;\n");
            },
            .int => {
                try out.appendSlice(arena, "    int64_t out_value = 0;\n");
                switch (input_wire) {
                    .void => try helpers.appendFmt(out, arena, "    int32_t status = {s}(&out_value);\n", .{ffi_name}),
                    .string => {
                        try out.appendSlice(arena, "    if (input == NULL) {\n");
                        try helpers.appendFmt(out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
                        try out.appendSlice(arena, "        return 0;\n");
                        try out.appendSlice(arena, "    }\n");
                        try out.appendSlice(arena, "    const char* input_utf = (*env)->GetStringUTFChars(env, input, NULL);\n");
                        try out.appendSlice(arena, "    if (input_utf == NULL) return 0;\n");
                        try helpers.appendFmt(out, arena, "    int32_t status = {s}((const uint8_t*)input_utf, strlen(input_utf), &out_value);\n", .{ffi_name});
                        try out.appendSlice(arena, "    (*env)->ReleaseStringUTFChars(env, input, input_utf);\n");
                    },
                    .int => try helpers.appendFmt(out, arena, "    int32_t status = {s}((int64_t)input, &out_value);\n", .{ffi_name}),
                    .bool => try helpers.appendFmt(out, arena, "    int32_t status = {s}(input ? 1 : 0, &out_value);\n", .{ffi_name}),
                }
                try out.appendSlice(arena, "    if (status != 0) {\n");
                try helpers.appendFmt(out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
                try out.appendSlice(arena, "        return 0;\n");
                try out.appendSlice(arena, "    }\n");
                try out.appendSlice(arena, "    return (jlong)out_value;\n");
            },
            .bool => {
                try out.appendSlice(arena, "    uint8_t out_value = 0;\n");
                switch (input_wire) {
                    .void => try helpers.appendFmt(out, arena, "    int32_t status = {s}(&out_value);\n", .{ffi_name}),
                    .string => {
                        try out.appendSlice(arena, "    if (input == NULL) {\n");
                        try helpers.appendFmt(out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
                        try out.appendSlice(arena, "        return JNI_FALSE;\n");
                        try out.appendSlice(arena, "    }\n");
                        try out.appendSlice(arena, "    const char* input_utf = (*env)->GetStringUTFChars(env, input, NULL);\n");
                        try out.appendSlice(arena, "    if (input_utf == NULL) return JNI_FALSE;\n");
                        try helpers.appendFmt(out, arena, "    int32_t status = {s}((const uint8_t*)input_utf, strlen(input_utf), &out_value);\n", .{ffi_name});
                        try out.appendSlice(arena, "    (*env)->ReleaseStringUTFChars(env, input, input_utf);\n");
                    },
                    .int => try helpers.appendFmt(out, arena, "    int32_t status = {s}((int64_t)input, &out_value);\n", .{ffi_name}),
                    .bool => try helpers.appendFmt(out, arena, "    int32_t status = {s}(input ? 1 : 0, &out_value);\n", .{ffi_name}),
                }
                try out.appendSlice(arena, "    if (status != 0) {\n");
                try helpers.appendFmt(out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
                try out.appendSlice(arena, "        return JNI_FALSE;\n");
                try out.appendSlice(arena, "    }\n");
                try out.appendSlice(arena, "    return out_value ? JNI_TRUE : JNI_FALSE;\n");
            },
            .void => {
                switch (input_wire) {
                    .void => try helpers.appendFmt(out, arena, "    int32_t status = {s}();\n", .{ffi_name}),
                    .string => {
                        try out.appendSlice(arena, "    if (input == NULL) {\n");
                        try helpers.appendFmt(out, arena, "        throw_structured_error(env, \"wizig.argument\", 1, \"{s} received null input\");\n", .{ffi_name});
                        try out.appendSlice(arena, "        return;\n");
                        try out.appendSlice(arena, "    }\n");
                        try out.appendSlice(arena, "    const char* input_utf = (*env)->GetStringUTFChars(env, input, NULL);\n");
                        try out.appendSlice(arena, "    if (input_utf == NULL) return;\n");
                        try helpers.appendFmt(out, arena, "    int32_t status = {s}((const uint8_t*)input_utf, strlen(input_utf));\n", .{ffi_name});
                        try out.appendSlice(arena, "    (*env)->ReleaseStringUTFChars(env, input, input_utf);\n");
                    },
                    .int => try helpers.appendFmt(out, arena, "    int32_t status = {s}((int64_t)input);\n", .{ffi_name}),
                    .bool => try helpers.appendFmt(out, arena, "    int32_t status = {s}(input ? 1 : 0);\n", .{ffi_name}),
                }
                try out.appendSlice(arena, "    if (status != 0) {\n");
                try helpers.appendFmt(out, arena, "        throw_status_error(env, \"{s}\", status);\n", .{ffi_name});
                try out.appendSlice(arena, "    }\n");
            },
        }
        try out.appendSlice(arena, "}\n\n");
    }
}
