//! C ABI bridge exposing Wizig runtime functions to native hosts.
//! Exports `wizig_runtime_*` entrypoints, `wizig_ffi_*` handshake symbols,
//! and structured last-error accessors with thread-local error envelopes.
const std = @import("std");
const builtin = @import("builtin");
const wizig_core = @import("wizig_core");
const ffi_error = @import("error.zig");

/// Re-exported for test access.
pub const Status = ffi_error.Status;

/// Opaque runtime handle; callers must treat as an opaque token.
pub const WizigRuntimeHandle = opaque {};

const statusCode = ffi_error.statusCode;
const domainLabel = ffi_error.domainLabel;
const setLastError = ffi_error.setLastError;
const clearLastError = ffi_error.clearLastError;

const bootstrap_allocator = std.heap.page_allocator;
const wizig_ffi_abi_version_value: u32 = 1;
const wizig_ffi_contract_hash_value: []const u8 =
    "0d2ca7c6c4d473945f98fef4240f4f4f5456bfec4a4cb8f90a322604dbf99795";

/// Build-mode-aware allocator type: `DebugAllocator` for leak detection in
/// debug builds, lightweight `SmpAllocator` wrapper for performance in release.
const Gpa = if (builtin.mode == .Debug)
    std.heap.DebugAllocator(.{ .thread_safe = true })
else
    ReleaseAllocator;

/// Minimal wrapper matching the `DebugAllocator` instance API so
/// `RuntimeBox` can use a single field type via `Gpa`.
const ReleaseAllocator = struct {
    pub const init: ReleaseAllocator = .{};

    pub fn allocator(_: *ReleaseAllocator) std.mem.Allocator {
        return std.heap.smp_allocator;
    }

    pub fn deinit(_: *ReleaseAllocator) std.heap.Check {
        return .ok;
    }
};

/// Per-runtime state behind the opaque handle.
const RuntimeBox = struct {
    runtime: wizig_core.Runtime,
    gpa: Gpa,

    fn allocator(self: *RuntimeBox) std.mem.Allocator {
        return self.gpa.allocator();
    }
};

fn toBox(handle: *WizigRuntimeHandle) *RuntimeBox {
    return @ptrCast(@alignCast(handle));
}

fn toHandle(box: *RuntimeBox) *WizigRuntimeHandle {
    return @ptrCast(box);
}

/// Returns whether a C ABI pointer may be safely sliced for `len` bytes.
fn hasBytes(ptr: [*]const u8, len: usize) bool {
    return len == 0 or @intFromPtr(ptr) != 0;
}

/// Converts a validated ABI byte pointer into a Zig slice.
fn bytesFromAbi(ptr: [*]const u8, len: usize) []const u8 {
    return if (len == 0) "" else ptr[0..len];
}

/// Returns generated FFI ABI version for host compatibility checks.
pub export fn wizig_ffi_abi_version() u32 {
    return wizig_ffi_abi_version_value;
}

/// Returns generated contract hash pointer for host compatibility checks.
pub export fn wizig_ffi_contract_hash_ptr() [*]const u8 {
    return wizig_ffi_contract_hash_value.ptr;
}

/// Returns generated contract hash length for host compatibility checks.
pub export fn wizig_ffi_contract_hash_len() usize {
    return wizig_ffi_contract_hash_value.len;
}

/// Returns structured error domain pointer for the current thread.
pub export fn wizig_ffi_last_error_domain_ptr() [*]const u8 {
    return domainLabel(ffi_error.last_error.domain).ptr;
}

/// Returns structured error domain length for the current thread.
pub export fn wizig_ffi_last_error_domain_len() usize {
    return domainLabel(ffi_error.last_error.domain).len;
}

/// Returns structured error code for the current thread.
pub export fn wizig_ffi_last_error_code() i32 {
    return ffi_error.last_error.code;
}

/// Returns structured error message pointer for the current thread.
pub export fn wizig_ffi_last_error_message_ptr() [*]const u8 {
    return ffi_error.last_error.message.ptr;
}

/// Returns structured error message length for the current thread.
pub export fn wizig_ffi_last_error_message_len() usize {
    return ffi_error.last_error.message.len;
}

/// Allocates and initializes a runtime handle for the provided app name.
pub export fn wizig_runtime_new(
    app_name_ptr: [*]const u8,
    app_name_len: usize,
    out_handle: ?*?*WizigRuntimeHandle,
) i32 {
    if (out_handle == null) return setLastError(.argument, statusCode(.null_argument), "null out_handle");
    const output = out_handle.?;
    output.* = null;
    if (app_name_len == 0) return setLastError(.argument, statusCode(.invalid_argument), "empty app name");
    if (!hasBytes(app_name_ptr, app_name_len)) {
        return setLastError(.argument, statusCode(.null_argument), "null app_name_ptr");
    }
    const app_name = bytesFromAbi(app_name_ptr, app_name_len);
    const box = bootstrap_allocator.create(RuntimeBox) catch
        return setLastError(.memory, statusCode(.out_of_memory), "out of memory");
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
/// Passing null is a no-op to simplify host-side cleanup code paths.
pub export fn wizig_runtime_free(handle: ?*WizigRuntimeHandle) void {
    if (handle == null) return;
    const box = toBox(handle.?);
    box.runtime.deinit();
    _ = box.gpa.deinit();
    bootstrap_allocator.destroy(box);
}

/// Executes runtime echo and returns an owned UTF-8 byte buffer.
/// On success, the caller owns `out_ptr[0..out_len]` and must release
/// it with `wizig_bytes_free`.
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
    if (!hasBytes(input_ptr, input_len)) {
        return setLastError(.argument, statusCode(.null_argument), "null input_ptr");
    }
    const input = bytesFromAbi(input_ptr, input_len);
    const echoed = box.runtime.echo(input, bootstrap_allocator) catch |err| switch (err) {
        error.OutOfMemory => return setLastError(.memory, statusCode(.out_of_memory), "out of memory"),
    };
    output_ptr.* = echoed.ptr;
    output_len.* = echoed.len;
    clearLastError();
    return statusCode(.ok);
}

/// Frees buffers returned by Wizig FFI functions.
/// Only accepts pointers returned by Wizig allocation paths.
pub export fn wizig_bytes_free(ptr: ?[*]u8, len: usize) void {
    if (ptr == null) return;
    bootstrap_allocator.free(ptr.?[0..len]);
}

test {
    _ = @import("error.zig");
    _ = @import("root_tests.zig");
}

test "Gpa type selection matches build mode" {
    try std.testing.expect(Gpa == if (builtin.mode == .Debug)
        std.heap.DebugAllocator(.{ .thread_safe = true })
    else
        ReleaseAllocator);
}
