//! Swift API class prelude renderer (init, validation, helper calls).
//!
//! All C symbols are resolved at link time via `import WizigFFI` -- no
//! dlopen/dlsym indirection.
//!
//! Performance notes:
//!   - `withUTF8Pointer` uses `String.withUTF8` (Swift 5.0+) for zero-copy
//!     pointer access, avoiding `Array(value.utf8)` heap allocation.
//!   - `callStringOutput` uses `String(decoding:as:)` to skip an
//!     intermediate `Data` allocation.
//!   - `callBinaryOutput` reads raw bytes from FFI and decodes via
//!     the generated `fromBinary` static method on each struct.

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

/// Appends the `WizigGeneratedApi` class body to `out`.
///
/// Includes: initializer, ABI/contract/wire-format validation, error reader,
/// status assertion, UTF-8 pointer helper, and typed call wrappers
/// (`callStringOutput`, `callIntOutput`, `callBoolOutput`,
/// `callBinaryOutput`, etc.).
pub fn appendApiClassCore(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
    _ = methods;
    try appendClassHeader(out, arena);
    try appendValidation(out, arena);
    try appendErrorReader(out, arena);
    try appendStatusHelper(out, arena);
    try appendUtf8Pointer(out, arena);
    try appendCallWrappers(out, arena);
}

/// Emits class declaration, sink property, and initializer.
fn appendClassHeader(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "public final class WizigGeneratedApi {\n");
    try out.appendSlice(arena, "    public weak var sink: WizigGeneratedEventSink?\n\n");
    try out.appendSlice(arena, "    public init(sink: WizigGeneratedEventSink? = nil) throws {\n");
    try out.appendSlice(arena, "        self.sink = sink\n");
    try out.appendSlice(arena, "        try validateBindings()\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits ABI version, contract hash, and wire format version validation.
fn appendValidation(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    private func validateBindings() throws {\n");
    try out.appendSlice(arena, "        let actualAbi = wizig_ffi_abi_version()\n");
    try out.appendSlice(arena, "        let hashPtr = wizig_ffi_contract_hash_ptr()\n");
    try out.appendSlice(arena, "        let hashLen = wizig_ffi_contract_hash_len()\n");
    try out.appendSlice(arena, "        let actualContractHash = hashLen > 0 ? String(decoding: UnsafeBufferPointer(start: hashPtr, count: hashLen), as: UTF8.self) : \"\"\n");
    try out.appendSlice(arena, "        let wireVersion = wizig_ffi_wire_format_version()\n");
    try out.appendSlice(arena, "        guard actualAbi == wizigExpectedAbiVersion, actualContractHash == wizigExpectedContractHash, wireVersion == wizigExpectedWireFormatVersion else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.compatibilityMismatch(\n");
    try out.appendSlice(arena, "                expectedAbi: wizigExpectedAbiVersion,\n");
    try out.appendSlice(arena, "                actualAbi: actualAbi,\n");
    try out.appendSlice(arena, "                expectedContractHash: wizigExpectedContractHash,\n");
    try out.appendSlice(arena, "                actualContractHash: actualContractHash\n");
    try out.appendSlice(arena, "            )\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits the `readLastError` helper.
fn appendErrorReader(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    private func readLastError() -> (domain: String, code: Int32, message: String) {\n");
    try out.appendSlice(arena, "        let domainPtr = wizig_ffi_last_error_domain_ptr()\n");
    try out.appendSlice(arena, "        let domainLen = wizig_ffi_last_error_domain_len()\n");
    try out.appendSlice(arena, "        let domain = domainLen > 0 ? String(decoding: UnsafeBufferPointer(start: domainPtr, count: domainLen), as: UTF8.self) : \"\"\n");
    try out.appendSlice(arena, "        let code = wizig_ffi_last_error_code()\n");
    try out.appendSlice(arena, "        let msgPtr = wizig_ffi_last_error_message_ptr()\n");
    try out.appendSlice(arena, "        let msgLen = wizig_ffi_last_error_message_len()\n");
    try out.appendSlice(arena, "        let message = msgLen > 0 ? String(decoding: UnsafeBufferPointer(start: msgPtr, count: msgLen), as: UTF8.self) : \"\"\n");
    try out.appendSlice(arena, "        return (domain, code, message)\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits `ensureStatus` and `withUTF8Pointer` helpers.
fn appendStatusHelper(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    private func ensureStatus(_ status: Int32, function: String) throws {\n");
    try out.appendSlice(arena, "        guard status == WizigGeneratedStatus.ok.rawValue else {\n");
    try out.appendSlice(arena, "            let detail = readLastError()\n");
    try out.appendSlice(arena, "            let resolvedCode = detail.code == 0 ? status : detail.code\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.ffiCallFailed(function: function, domain: detail.domain, code: resolvedCode, message: detail.message)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits `withUTF8Pointer` for zero-copy string input passing.
fn appendUtf8Pointer(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    /// Zero-copy UTF-8 pointer access for FFI string inputs.\n");
    try out.appendSlice(arena, "    /// Uses String.withUTF8 (Swift 5.0+) to avoid heap-allocating an Array<UInt8> copy.\n");
    try out.appendSlice(arena, "    private func withUTF8Pointer<T>(_ value: String, _ body: (UnsafePointer<UInt8>, Int) throws -> T) throws -> T {\n");
    try out.appendSlice(arena, "        var copy = value\n");
    try out.appendSlice(arena, "        return try copy.withUTF8 { buffer in\n");
    try out.appendSlice(arena, "            if buffer.isEmpty {\n");
    try out.appendSlice(arena, "                var placeholder: UInt8 = 0\n");
    try out.appendSlice(arena, "                return try withUnsafePointer(to: &placeholder) { try body($0, 0) }\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "            return try body(buffer.baseAddress!, buffer.count)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    private func withBinaryPointer<T>(_ value: [UInt8], _ body: (UnsafePointer<UInt8>, Int) throws -> T) throws -> T {\n");
    try out.appendSlice(arena, "        if value.isEmpty {\n");
    try out.appendSlice(arena, "            var placeholder: UInt8 = 0\n");
    try out.appendSlice(arena, "            return try withUnsafePointer(to: &placeholder) { try body($0, 0) }\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return try value.withUnsafeBufferPointer { buf in\n");
    try out.appendSlice(arena, "            try body(buf.baseAddress!, buf.count)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits typed call wrappers for each output kind.
fn appendCallWrappers(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try appendCallStringOutput(out, arena);
    try appendCallIntOutput(out, arena);
    try appendCallBoolOutput(out, arena);
    try appendCallEnumOutput(out, arena);
    try appendCallBinaryOutput(out, arena);
    try appendCallVoidOutput(out, arena);
}

/// Emits `callStringOutput` wrapper.
fn appendCallStringOutput(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    private func callStringOutput(function: String, _ invoke: (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, UnsafeMutablePointer<Int>) -> Int32) throws -> String {\n");
    try out.appendSlice(arena, "        var outPtr: UnsafeMutablePointer<UInt8>?\n");
    try out.appendSlice(arena, "        var outLen = 0\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(&outPtr, &outLen), function: function)\n");
    try out.appendSlice(arena, "        guard let outPtr else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.unexpectedNullOutput(function: function)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        defer {\n");
    try out.appendSlice(arena, "            wizig_bytes_free(outPtr, outLen)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return String(decoding: UnsafeBufferPointer(start: outPtr, count: outLen), as: UTF8.self)\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits `callIntOutput` wrapper.
fn appendCallIntOutput(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    private func callIntOutput(function: String, _ invoke: (UnsafeMutablePointer<Int64>) -> Int32) throws -> Int64 {\n");
    try out.appendSlice(arena, "        var out: Int64 = 0\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(&out), function: function)\n");
    try out.appendSlice(arena, "        return out\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits `callBoolOutput` wrapper.
fn appendCallBoolOutput(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    private func callBoolOutput(function: String, _ invoke: (UnsafeMutablePointer<UInt8>) -> Int32) throws -> Bool {\n");
    try out.appendSlice(arena, "        var out: UInt8 = 0\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(&out), function: function)\n");
    try out.appendSlice(arena, "        return out != 0\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits `callEnumOutput` wrapper.
fn appendCallEnumOutput(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    private func callEnumOutput<T: RawRepresentable>(function: String, _ invoke: (UnsafeMutablePointer<Int64>) -> Int32) throws -> T where T.RawValue == Int64 {\n");
    try out.appendSlice(arena, "        let raw = try callIntOutput(function: function, invoke)\n");
    try out.appendSlice(arena, "        guard let value = T(rawValue: raw) else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.invalidEnumRawValue(function: function, rawValue: raw, typeName: String(describing: T.self))\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return value\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits `callBinaryOutput` wrapper for binary struct decoding.
fn appendCallBinaryOutput(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    private func callBinaryOutput<T>(function: String, decode: (UnsafeRawPointer, Int) throws -> T, _ invoke: (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, UnsafeMutablePointer<Int>) -> Int32) throws -> T {\n");
    try out.appendSlice(arena, "        var outPtr: UnsafeMutablePointer<UInt8>?\n");
    try out.appendSlice(arena, "        var outLen = 0\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(&outPtr, &outLen), function: function)\n");
    try out.appendSlice(arena, "        guard let outPtr else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.unexpectedNullOutput(function: function)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        defer { wizig_bytes_free(outPtr, outLen) }\n");
    try out.appendSlice(arena, "        return try decode(UnsafeRawPointer(outPtr), outLen)\n");
    try out.appendSlice(arena, "    }\n\n");
}

/// Emits `callVoidOutput` wrapper.
fn appendCallVoidOutput(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "    private func callVoidOutput(function: String, _ invoke: () -> Int32) throws {\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(), function: function)\n");
    try out.appendSlice(arena, "    }\n\n");
}
