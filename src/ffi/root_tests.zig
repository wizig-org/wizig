//! Integration tests for the Wizig FFI C ABI surface.
//!
//! Exercises runtime lifecycle (new/free), echo round-trips, structured
//! error reporting, and null-pointer rejection across the exported symbols.
const std = @import("std");
const root = @import("root.zig");

const RuntimeNewWithNullableInput = *const fn (?[*]const u8, usize, ?*?*root.WizigRuntimeHandle) callconv(.c) i32;
const RuntimeEchoWithNullableInput = *const fn (?*root.WizigRuntimeHandle, ?[*]const u8, usize, ?*?[*]u8, ?*usize) callconv(.c) i32;

test "ffi runtime round trip and handshake exports" {
    var handle: ?*root.WizigRuntimeHandle = null;
    try std.testing.expectEqual(@intFromEnum(root.Status.ok), root.wizig_runtime_new("demo".ptr, "demo".len, &handle));
    defer root.wizig_runtime_free(handle);

    var output_ptr: ?[*]u8 = null;
    var output_len: usize = 0;
    try std.testing.expectEqual(
        @intFromEnum(root.Status.ok),
        root.wizig_runtime_echo(handle, "hello".ptr, "hello".len, &output_ptr, &output_len),
    );
    defer root.wizig_bytes_free(output_ptr, output_len);

    try std.testing.expect(output_ptr != null);
    try std.testing.expectEqualStrings("demo:hello", output_ptr.?[0..output_len]);
    try std.testing.expectEqual(@as(u32, 1), root.wizig_ffi_abi_version());
    try std.testing.expect(root.wizig_ffi_contract_hash_len() > 0);
}

test "ffi structured error is populated for invalid arguments" {
    try std.testing.expectEqual(
        @intFromEnum(root.Status.null_argument),
        root.wizig_runtime_echo(null, "x".ptr, "x".len, null, null),
    );
    try std.testing.expectEqual(@intFromEnum(root.Status.null_argument), root.wizig_ffi_last_error_code());

    const domain = root.wizig_ffi_last_error_domain_ptr()[0..root.wizig_ffi_last_error_domain_len()];
    const message = root.wizig_ffi_last_error_message_ptr()[0..root.wizig_ffi_last_error_message_len()];
    try std.testing.expectEqualStrings("wizig.argument", domain);
    try std.testing.expect(message.len > 0);
}

test "ffi rejects null app name pointers" {
    var handle: ?*root.WizigRuntimeHandle = null;
    const runtime_new: RuntimeNewWithNullableInput = @ptrCast(&root.wizig_runtime_new);

    try std.testing.expectEqual(
        @intFromEnum(root.Status.null_argument),
        runtime_new(null, 4, &handle),
    );
    try std.testing.expect(handle == null);
    try std.testing.expectEqual(@intFromEnum(root.Status.null_argument), root.wizig_ffi_last_error_code());
    try std.testing.expectEqualStrings(
        "null app_name_ptr",
        root.wizig_ffi_last_error_message_ptr()[0..root.wizig_ffi_last_error_message_len()],
    );
}

test "ffi accepts empty echo input without dereferencing the pointer" {
    var handle: ?*root.WizigRuntimeHandle = null;
    try std.testing.expectEqual(@intFromEnum(root.Status.ok), root.wizig_runtime_new("demo".ptr, "demo".len, &handle));
    defer root.wizig_runtime_free(handle);

    const runtime_echo: RuntimeEchoWithNullableInput = @ptrCast(&root.wizig_runtime_echo);
    var output_ptr: ?[*]u8 = null;
    var output_len: usize = 0;
    try std.testing.expectEqual(
        @intFromEnum(root.Status.ok),
        runtime_echo(handle, null, 0, &output_ptr, &output_len),
    );
    defer root.wizig_bytes_free(output_ptr, output_len);

    try std.testing.expect(output_ptr != null);
    try std.testing.expectEqualStrings("demo:", output_ptr.?[0..output_len]);
}

test "ffi rejects null non-empty echo input pointers" {
    var handle: ?*root.WizigRuntimeHandle = null;
    try std.testing.expectEqual(@intFromEnum(root.Status.ok), root.wizig_runtime_new("demo".ptr, "demo".len, &handle));
    defer root.wizig_runtime_free(handle);

    const runtime_echo: RuntimeEchoWithNullableInput = @ptrCast(&root.wizig_runtime_echo);
    var output_ptr: ?[*]u8 = null;
    var output_len: usize = 0;
    try std.testing.expectEqual(
        @intFromEnum(root.Status.null_argument),
        runtime_echo(handle, null, 1, &output_ptr, &output_len),
    );
    try std.testing.expect(output_ptr == null);
    try std.testing.expectEqual(@as(usize, 0), output_len);
}
