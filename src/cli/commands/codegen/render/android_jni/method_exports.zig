//! Per-method Android JNI export generation.
//!
//! Generates `JNIEXPORT` C functions that bridge each `ApiMethod` from
//! Kotlin/Java to the underlying Wizig FFI C ABI.  Struct parameters use
//! `jbyteArray` for binary wire format transport; plain strings use
//! `jstring` with `GetStringUTFLength` (O(1)) for encoded length.

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");
const method_call_inputs = @import("method_call_inputs.zig");

/// Appends one `JNIEXPORT` function per method to `out`.
///
/// Each generated function:
///   1. Validates / converts the Java input value.
///   2. Calls the corresponding `wizig_api_<name>` FFI symbol.
///   3. Converts the output back to a JNI type and returns it.
pub fn appendMethodExports(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
    for (methods) |method| {
        const ffi_name = try std.fmt.allocPrint(arena, "wizig_api_{s}", .{method.name});
        const jni_name = try helpers.jniEscape(arena, ffi_name);
        try helpers.appendFmt(
            out,
            arena,
            "JNIEXPORT {s} JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_{s}(JNIEnv* env, jclass clazz",
            .{ helpers.jniCType(method.output), jni_name },
        );
        try appendInputParam(out, arena, method.input);
        try out.appendSlice(arena, ") {\n");
        try out.appendSlice(arena, "    (void)clazz;\n");
        try method_call_inputs.appendMethodBody(out, arena, ffi_name, method);
        try out.appendSlice(arena, "}\n\n");
    }
}

/// Emits the JNI input parameter declaration.
fn appendInputParam(out: *std.ArrayList(u8), arena: std.mem.Allocator, input: api.ApiType) !void {
    switch (input) {
        .void => {},
        .user_struct => try out.appendSlice(arena, ", jbyteArray input"),
        .string => try out.appendSlice(arena, ", jstring input"),
        .int, .user_enum => try out.appendSlice(arena, ", jlong input"),
        .bool => try out.appendSlice(arena, ", jboolean input"),
    }
}
