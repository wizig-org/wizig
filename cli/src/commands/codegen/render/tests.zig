//! Regression tests for generated renderer outputs.

const std = @import("std");
const compatibility = @import("../compatibility.zig");
const api = @import("../model/api.zig");
const zig_ffi_root = @import("zig_ffi_root.zig");
const swift_api = @import("swift_api.zig");
const kotlin_api = @import("kotlin_api.zig");
const android_jni_bridge = @import("android_jni_bridge.zig");
const ios_c_headers = @import("ios_c_headers.zig");

test "renderZigFfiRoot emits compatibility handshake and structured error symbols" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var methods = [_]api.ApiMethod{
        .{ .name = "echo", .input = .string, .output = .string },
        .{ .name = "uptime", .input = .void, .output = .int },
    };
    var events = [_]api.ApiEvent{
        .{ .name = "log", .payload = .string },
    };
    const spec: api.ApiSpec = .{
        .namespace = "dev.wizig.codegen.tests",
        .methods = methods[0..],
        .events = events[0..],
    };

    const compat_meta = try compatibility.buildMetadata(arena, spec.namespace, spec.methods, spec.events);
    const rendered = try zig_ffi_root.renderZigFfiRoot(arena, spec, compat_meta);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_ffi_abi_version() u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_ffi_contract_hash_ptr() [*]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_ffi_last_error_domain_ptr() [*]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_ffi_last_error_code() i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_runtime_new(app_name_ptr: [*]const u8, app_name_len: usize, out_handle: ?*?*WizigRuntimeHandle) i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "pub export fn wizig_runtime_echo(handle: ?*WizigRuntimeHandle, input_ptr: [*]const u8, input_len: usize, out_ptr: ?*?[*]u8, out_len: ?*usize) i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "std.fmt.allocPrint(allocator, \"{s}:{s}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "fn setLastError(domain: ErrorDomain, code: i32, message: []const u8) i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, compat_meta.contract_hash_hex) != null);
}

test "renderSwiftApi emits compatibility checks and structured ffi error mapping" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var methods = [_]api.ApiMethod{
        .{ .name = "echo", .input = .string, .output = .string },
    };
    var events = [_]api.ApiEvent{
        .{ .name = "log", .payload = .string },
    };
    const spec: api.ApiSpec = .{
        .namespace = "dev.wizig.codegen.tests",
        .methods = methods[0..],
        .events = events[0..],
    };

    const compat_meta = try compatibility.buildMetadata(arena, spec.namespace, spec.methods, spec.events);
    const rendered = try swift_api.renderSwiftApi(arena, spec, compat_meta);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "case compatibilityMismatch(expectedAbi: UInt32, actualAbi: UInt32, expectedContractHash: String, actualContractHash: String)") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "case ffiCallFailed(function: String, domain: String, code: Int32, message: String)") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "wizig_ffi_last_error_domain_ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "wizig_ffi_last_error_message_ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "func readLastError() -> (domain: String, code: Int32, message: String)") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "WizigFFI.framework/WizigFFI") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Self.defaultLibraryCandidates()") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, compat_meta.contract_hash_hex) != null);
}

test "renderKotlinApi and renderAndroidJniBridge emit compatibility and structured errors" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var methods = [_]api.ApiMethod{
        .{ .name = "echo", .input = .string, .output = .string },
    };
    var events = [_]api.ApiEvent{
        .{ .name = "log", .payload = .string },
    };
    const spec: api.ApiSpec = .{
        .namespace = "dev.wizig.codegen.tests",
        .methods = methods[0..],
        .events = events[0..],
    };

    const compat_meta = try compatibility.buildMetadata(arena, spec.namespace, spec.methods, spec.events);
    const kotlin_rendered = try kotlin_api.renderKotlinApi(arena, spec, compat_meta);

    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "private const val WIZIG_EXPECTED_ABI_VERSION: Int =") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "private const val WIZIG_EXPECTED_CONTRACT_HASH: String =") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, "class WizigGeneratedFfiException(") != null);
    try std.testing.expect(std.mem.indexOf(u8, kotlin_rendered, compat_meta.contract_hash_hex) != null);

    const jni_rendered = try android_jni_bridge.renderAndroidJniBridge(arena, spec, compat_meta);

    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "extern uint32_t wizig_ffi_abi_version(void);") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "extern const uint8_t* wizig_ffi_last_error_domain_ptr(void);") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "throw_structured_error(env, \"wizig.compatibility\", 1002, message);") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "ffi compatibility mismatch: expected abi=%u hash=%s got abi=%u hash=%s") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "#include <android/log.h>") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "static void wizig_forward_stdio_to_logcat_once(void)") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, "wizig_forward_stdio_to_logcat_once();") != null);
    try std.testing.expect(std.mem.indexOf(u8, jni_rendered, compat_meta.contract_hash_hex) != null);
}

test "render iOS C headers expose method exports and framework modulemap" {
    var arena_impl = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var methods = [_]api.ApiMethod{
        .{ .name = "echo", .input = .string, .output = .string },
        .{ .name = "uptime", .input = .void, .output = .int },
        .{ .name = "set_enabled", .input = .bool, .output = .void },
    };
    const spec: api.ApiSpec = .{
        .namespace = "dev.wizig.codegen.tests",
        .methods = methods[0..],
        .events = &.{},
    };

    const generated_header = try ios_c_headers.renderGeneratedApiHeader(arena, spec);
    const umbrella_header = try ios_c_headers.renderFrameworkUmbrellaHeader(arena);
    const modulemap = try ios_c_headers.renderFrameworkModuleMap(arena);

    try std.testing.expect(std.mem.indexOf(u8, generated_header, "int32_t wizig_api_echo(const uint8_t* input_ptr, size_t input_len, uint8_t** out_ptr, size_t* out_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_header, "int32_t wizig_api_uptime(int64_t* out_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_header, "int32_t wizig_api_set_enabled(uint8_t input);") != null);
    try std.testing.expect(std.mem.indexOf(u8, umbrella_header, "#include \"wizig.h\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, umbrella_header, "#include \"WizigGeneratedApi.h\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, modulemap, "framework module WizigFFI") != null);
    try std.testing.expect(std.mem.indexOf(u8, modulemap, "umbrella header \"WizigFFI.h\"") != null);
}
