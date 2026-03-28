//! Structured error types and thread-local state for the Wizig FFI layer.
//!
//! Defines the error envelope model used across all exported FFI functions,
//! including status codes, error domains, and thread-local error storage.
const std = @import("std");

/// Stable status codes returned by exported FFI functions.
///
/// Numeric values are part of the public C ABI.
/// Host bindings may treat these as transport-level outcomes.
/// Rich diagnostics are available via `wizig_ffi_last_error_*`.
pub const Status = enum(i32) {
    ok = 0,
    null_argument = 1,
    out_of_memory = 2,
    invalid_argument = 3,
    internal_error = 255,
};

/// Stable symbolic domains for structured errors.
///
/// Domains separate broad failure classes so host layers can map them to
/// platform-native error taxonomies without parsing free-form messages.
pub const ErrorDomain = enum(u32) {
    none = 0,
    argument = 1,
    memory = 2,
    runtime = 3,
    compatibility = 4,
};

/// Thread-local structured error envelope.
///
/// The envelope is per-thread and overwritten on each FFI call that updates
/// error state. Callers should snapshot values immediately after a failure.
pub const LastError = struct {
    domain: ErrorDomain = .none,
    code: i32 = 0,
    message: []const u8 = "ok",
};

/// Thread-local error state shared across all FFI exports.
pub threadlocal var last_error: LastError = .{};

/// Converts a `Status` enum to its underlying C ABI integer.
pub fn statusCode(status: Status) i32 {
    return @intFromEnum(status);
}

/// Maps an `ErrorDomain` to its canonical string label.
pub fn domainLabel(domain: ErrorDomain) []const u8 {
    return switch (domain) {
        .none => "wizig.ok",
        .argument => "wizig.argument",
        .memory => "wizig.memory",
        .runtime => "wizig.runtime",
        .compatibility => "wizig.compatibility",
    };
}

/// Resets the thread-local error envelope to its default (no-error) state.
pub fn clearLastError() void {
    last_error = .{};
}

/// Populates the thread-local error envelope and returns `code`.
pub fn setLastError(domain: ErrorDomain, code: i32, message: []const u8) i32 {
    last_error = .{ .domain = domain, .code = code, .message = message };
    return code;
}

test "status code round-trip preserves ABI values" {
    try std.testing.expectEqual(@as(i32, 0), statusCode(.ok));
    try std.testing.expectEqual(@as(i32, 1), statusCode(.null_argument));
    try std.testing.expectEqual(@as(i32, 2), statusCode(.out_of_memory));
    try std.testing.expectEqual(@as(i32, 3), statusCode(.invalid_argument));
    try std.testing.expectEqual(@as(i32, 255), statusCode(.internal_error));
}

test "domain labels map to canonical strings" {
    try std.testing.expectEqualStrings("wizig.ok", domainLabel(.none));
    try std.testing.expectEqualStrings("wizig.argument", domainLabel(.argument));
    try std.testing.expectEqualStrings("wizig.memory", domainLabel(.memory));
    try std.testing.expectEqualStrings("wizig.runtime", domainLabel(.runtime));
    try std.testing.expectEqualStrings("wizig.compatibility", domainLabel(.compatibility));
}

test "setLastError writes and clearLastError resets thread-local state" {
    _ = setLastError(.memory, 2, "test error");
    try std.testing.expectEqual(@as(i32, 2), last_error.code);
    try std.testing.expectEqualStrings("test error", last_error.message);
    try std.testing.expect(last_error.domain == .memory);
    clearLastError();
    try std.testing.expectEqual(@as(i32, 0), last_error.code);
    try std.testing.expectEqualStrings("ok", last_error.message);
    try std.testing.expect(last_error.domain == .none);
}
