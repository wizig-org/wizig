const std = @import("std");
const compatibility = @import("../compatibility.zig");
const api = @import("../model/api.zig");
const zig_ffi_root = @import("zig_ffi_root.zig");
const swift_api = @import("swift_api.zig");
const kotlin_api = @import("kotlin_api.zig");
const android_jni_bridge = @import("android_jni_bridge.zig");
const ios_c_headers = @import("ios_c_headers.zig");
const ios_c_shim = @import("ios_c_shim.zig");

test "all renderers include user struct and enum wire handling" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var methods = [_]api.ApiMethod{
        .{ .name = "save_profile", .input = .{ .user_struct = "UserProfile" }, .output = .void },
        .{ .name = "favorite_color", .input = .void, .output = .{ .user_enum = "Color" } },
        .{ .name = "set_color", .input = .{ .user_enum = "Color" }, .output = .void },
        .{ .name = "load_profile", .input = .void, .output = .{ .user_struct = "UserProfile" } },
    };
    var structs = [_]api.UserStruct{
        .{ .name = "UserProfile", .fields = &.{
            .{ .name = "name", .field_type = .string },
            .{ .name = "favorite", .field_type = .{ .user_enum = "Color" } },
        } },
    };
    var enums = [_]api.UserEnum{
        .{ .name = "Color", .variants = &.{ "red", "green" } },
    };
    const spec: api.ApiSpec = .{
        .namespace = "dev.wizig.codegen.tests",
        .methods = methods[0..],
        .events = &.{},
        .structs = structs[0..],
        .enums = enums[0..],
    };

    const compat_meta = try compatibility.buildMetadata(arena, spec);
    const zig_rendered = try zig_ffi_root.renderZigFfiRoot(arena, spec, compat_meta);
    const swift_rendered = try swift_api.renderSwiftApi(arena, spec, compat_meta);
    const kotlin_rendered = try kotlin_api.renderKotlinApi(arena, spec, compat_meta);
    const jni_rendered = try android_jni_bridge.renderAndroidJniBridge(arena, spec, compat_meta);
    const ios_header = try ios_c_headers.renderGeneratedApiHeader(arena, spec);

    try std.testing.expect(std.mem.indexOf(u8, zig_rendered, "const UserProfile = app.UserProfile;") != null);
    try std.testing.expect(std.mem.indexOf(u8, zig_rendered, "wireReadString(input_bytes, &wire_off)") != null);
    try std.testing.expect(std.mem.indexOf(u8, zig_rendered, "wireWriteString(&wire_buf, ffi_output_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, zig_rendered, "std.enums.fromInt(Color, input)") != null);
    try std.testing.expect(std.mem.indexOf(u8, zig_rendered, "@intFromEnum(value)") != null);

    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "public struct UserProfile {") != null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "public enum Color: Int64, CaseIterable {") != null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "Codable") == null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "callBinaryOutput") != null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "input.toBinary()") != null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "withBinaryPointer(binaryInput)") != null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "try r.readString()") != null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "fileprivate static func fromBinaryReader") != null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "invalidEnumRawValue(function: \"wire\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "import Foundation") == null);
    try std.testing.expect(std.mem.indexOf(u8, swift_rendered, "private let wizigExpectedWireFormatVersion: UInt32 = 1") != null);

    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "data class UserProfile(") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "enum class Color(val rawValue: Long)") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "val wireInput = input.toBinary()") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "Color.fromRaw(wireOutput)") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "return UserProfile.fromBinary(wireOutput)") != null);

    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "extern int32_t wizig_api_save_profile(const uint8_t* input_ptr, size_t input_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "extern int32_t wizig_api_favorite_color(int64_t* out_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "JNIEXPORT void JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_wizig_1api_1save_1profile(JNIEnv* env, jclass clazz, jbyteArray input)") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "JNIEXPORT jlong JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_wizig_1api_1favorite_1color(JNIEnv* env, jclass clazz)") != null);

    try std.testing.expect(std.mem.indexOf(u8, ios_header, "int32_t wizig_api_save_profile(const uint8_t* input_ptr, size_t input_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, ios_header, "int32_t wizig_api_favorite_color(int64_t* out_value);") != null);
}

test "iOS SwiftPM shim forwards runtime and API symbols" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const spec: api.ApiSpec = .{
        .namespace = "dev.wizig.codegen.tests",
        .methods = &.{.{ .name = "echo", .input = .string, .output = .string }},
        .events = &.{},
    };

    const shim = try ios_c_shim.renderIosSwiftPmShim(arena, spec);
    try std.testing.expect(std.mem.indexOf(u8, shim, "dlopen(\"@executable_path/Frameworks/WizigFFI.framework/WizigFFI\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "int32_t wizig_runtime_new(") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "uint32_t wizig_ffi_wire_format_version(void)") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "int32_t wizig_api_echo(") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "wizigffi_resolve(\"wizig_api_echo\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, shim, "wizigffi_resolve(\"wizig_ffi_wire_format_version\")") != null);
}
