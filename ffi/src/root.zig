//! C ABI bridge exposing Wizig runtime functions to native hosts.
//!
//! ## Compatibility Surface
//! This module exports:
//! - runtime entrypoints (`wizig_runtime_*`)
//! - ABI/version handshake symbols (`wizig_ffi_*`)
//! - structured last-error accessors (`domain/code/message`)
//!
//! ## Error Model
//! Calls still return stable integer status codes for C ABI compatibility.
//! Additionally, failures write a structured thread-local error envelope so
//! higher-level host bindings can surface richer diagnostics.
const std = @import("std");
const wizig_core = @import("wizig_core");

/// Stable status codes returned by exported FFI functions.
///
/// ## Contract
/// - Numeric values are part of the public C ABI.
/// - Host bindings may treat these as transport-level outcomes.
/// - Rich diagnostics are available via `wizig_ffi_last_error_*`.
pub const Status = enum(i32) {
    ok = 0,
    null_argument = 1,
    out_of_memory = 2,
    invalid_argument = 3,
    internal_error = 255,
};

/// Stable symbolic domains for structured errors.
///
/// ## Purpose
/// Domains separate broad failure classes so host layers can map them to
/// platform-native error taxonomies without parsing free-form messages.
const ErrorDomain = enum(u32) {
    none = 0,
    argument = 1,
    memory = 2,
    runtime = 3,
    compatibility = 4,
};

/// Thread-local structured error envelope.
///
/// ## Lifetime
/// The envelope is per-thread and overwritten on each FFI call that updates
/// error state. Callers should snapshot values immediately after a failure.
const LastError = struct {
    domain: ErrorDomain = .none,
    code: i32 = 0,
    message: []const u8 = "ok",
};

/// Opaque runtime handle used by C/Swift/Kotlin callers.
///
/// ## Safety
/// The pointee layout is private to Zig; callers must treat this as an opaque
/// token and only pass it back to exported Wizig functions.
pub const WizigRuntimeHandle = opaque {};

const bootstrap_allocator = std.heap.page_allocator;
const wizig_ffi_abi_version_value: u32 = 1;
const wizig_ffi_contract_hash_value: []const u8 = "0d2ca7c6c4d473945f98fef4240f4f4f5456bfec4a4cb8f90a322604dbf99795";

threadlocal var last_error: LastError = .{};

const RuntimeBox = struct {
    runtime: wizig_core.Runtime,
    gpa: std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }),

    fn allocator(self: *RuntimeBox) std.mem.Allocator {
        return self.gpa.allocator();
    }
};

fn statusCode(status: Status) i32 {
    return @intFromEnum(status);
}

fn domainLabel(domain: ErrorDomain) []const u8 {
    return switch (domain) {
        .none => "wizig.ok",
        .argument => "wizig.argument",
        .memory => "wizig.memory",
        .runtime => "wizig.runtime",
        .compatibility => "wizig.compatibility",
    };
}

fn clearLastError() void {
    last_error = .{};
}

fn setLastError(domain: ErrorDomain, code: i32, message: []const u8) i32 {
    last_error = .{ .domain = domain, .code = code, .message = message };
    return code;
}

fn toBox(handle: *WizigRuntimeHandle) *RuntimeBox {
    return @ptrCast(@alignCast(handle));
}

fn toHandle(box: *RuntimeBox) *WizigRuntimeHandle {
    return @ptrCast(box);
}

/// Returns generated FFI ABI version for host compatibility checks.
///
/// ## Handshake
/// Host bridges compare this value against their compiled expectation before
/// invoking method entrypoints.
pub export fn wizig_ffi_abi_version() u32 {
    return wizig_ffi_abi_version_value;
}

/// Returns generated contract hash pointer for host compatibility checks.
///
/// ## Handshake
/// This hash represents the generated API contract expected by host bindings.
pub export fn wizig_ffi_contract_hash_ptr() [*]const u8 {
    return wizig_ffi_contract_hash_value.ptr;
}

/// Returns generated contract hash length for host compatibility checks.
pub export fn wizig_ffi_contract_hash_len() usize {
    return wizig_ffi_contract_hash_value.len;
}

/// Returns structured error domain pointer for the current thread.
///
/// ## Usage
/// Read this immediately after a non-`ok` status to retrieve the latest
/// structured error envelope for the current thread.
pub export fn wizig_ffi_last_error_domain_ptr() [*]const u8 {
    return domainLabel(last_error.domain).ptr;
}

/// Returns structured error domain length for the current thread.
pub export fn wizig_ffi_last_error_domain_len() usize {
    return domainLabel(last_error.domain).len;
}

/// Returns structured error code for the current thread.
pub export fn wizig_ffi_last_error_code() i32 {
    return last_error.code;
}

/// Returns structured error message pointer for the current thread.
pub export fn wizig_ffi_last_error_message_ptr() [*]const u8 {
    return last_error.message.ptr;
}

/// Returns structured error message length for the current thread.
pub export fn wizig_ffi_last_error_message_len() usize {
    return last_error.message.len;
}

/// Allocates and initializes a runtime handle for the provided app name.
///
/// ## Preconditions
/// - `out_handle` must be non-null.
/// - `app_name_len` must be greater than zero.
///
/// ## Postconditions
/// - On success, writes a non-null handle to `out_handle`.
/// - On failure, writes null and updates thread-local structured error state.
pub export fn wizig_runtime_new(
    app_name_ptr: [*]const u8,
    app_name_len: usize,
    out_handle: ?*?*WizigRuntimeHandle,
) i32 {
    if (out_handle == null) return setLastError(.argument, statusCode(.null_argument), "null out_handle");
    const output = out_handle.?;
    output.* = null;

    if (app_name_len == 0) return setLastError(.argument, statusCode(.invalid_argument), "empty app name");
    const app_name = app_name_ptr[0..app_name_len];

    const box = bootstrap_allocator.create(RuntimeBox) catch return setLastError(.memory, statusCode(.out_of_memory), "out of memory");
    errdefer bootstrap_allocator.destroy(box);

    box.gpa = .init;

    const gpa_allocator = box.gpa.allocator();
    box.runtime = wizig_core.Runtime.init(gpa_allocator, app_name) catch |err| switch (err) {
        error.OutOfMemory => return setLastError(.memory, statusCode(.out_of_memory), "out of memory"),
    };

    output.* = toHandle(box);
    clearLastError();
    return statusCode(.ok);
}

/// Destroys a runtime handle previously returned by `wizig_runtime_new`.
///
/// ## Semantics
/// Passing null is a no-op to simplify host-side cleanup code paths.
pub export fn wizig_runtime_free(handle: ?*WizigRuntimeHandle) void {
    if (handle == null) return;

    const box = toBox(handle.?);
    box.runtime.deinit();
    _ = box.gpa.deinit();
    bootstrap_allocator.destroy(box);
}

/// Executes runtime echo and returns an owned UTF-8 byte buffer.
///
/// ## Ownership
/// On success, the caller owns `out_ptr[0..out_len]` and must release it with
/// `wizig_bytes_free`.
pub export fn wizig_runtime_echo(
    handle: ?*WizigRuntimeHandle,
    input_ptr: [*]const u8,
    input_len: usize,
    out_ptr: ?*?[*]u8,
    out_len: ?*usize,
) i32 {
    if (handle == null or out_ptr == null or out_len == null) {
        return setLastError(.argument, statusCode(.null_argument), "null argument");
    }

    const output_ptr = out_ptr.?;
    const output_len = out_len.?;
    output_ptr.* = null;
    output_len.* = 0;

    const box = toBox(handle.?);
    const input = input_ptr[0..input_len];

    // Allocate result with page_allocator since wizig_bytes_free is handle-free
    const echoed = box.runtime.echo(input, bootstrap_allocator) catch |err| switch (err) {
        error.OutOfMemory => return setLastError(.memory, statusCode(.out_of_memory), "out of memory"),
    };

    output_ptr.* = echoed.ptr;
    output_len.* = echoed.len;
    clearLastError();
    return statusCode(.ok);
}

/// Frees buffers returned by Wizig FFI functions.
///
/// ## Ownership
/// This function only accepts pointers returned by Wizig allocation paths.
pub export fn wizig_bytes_free(ptr: ?[*]u8, len: usize) void {
    if (ptr == null) return;
    bootstrap_allocator.free(ptr.?[0..len]);
}

test "ffi runtime round trip and handshake exports" {
    var handle: ?*WizigRuntimeHandle = null;
    try std.testing.expectEqual(statusCode(.ok), wizig_runtime_new("demo".ptr, "demo".len, &handle));
    defer wizig_runtime_free(handle);

    var output_ptr: ?[*]u8 = null;
    var output_len: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        wizig_runtime_echo(handle, "hello".ptr, "hello".len, &output_ptr, &output_len),
    );
    defer wizig_bytes_free(output_ptr, output_len);

    try std.testing.expect(output_ptr != null);
    try std.testing.expectEqualStrings("demo:hello", output_ptr.?[0..output_len]);
    try std.testing.expectEqual(wizig_ffi_abi_version_value, wizig_ffi_abi_version());
    try std.testing.expect(wizig_ffi_contract_hash_len() > 0);
}

test "ffi structured error is populated for invalid arguments" {
    try std.testing.expectEqual(
        statusCode(.null_argument),
        wizig_runtime_echo(null, "x".ptr, "x".len, null, null),
    );
    try std.testing.expectEqual(statusCode(.null_argument), wizig_ffi_last_error_code());

    const domain = wizig_ffi_last_error_domain_ptr()[0..wizig_ffi_last_error_domain_len()];
    const message = wizig_ffi_last_error_message_ptr()[0..wizig_ffi_last_error_message_len()];
    try std.testing.expectEqualStrings("wizig.argument", domain);
    try std.testing.expect(message.len > 0);
}
