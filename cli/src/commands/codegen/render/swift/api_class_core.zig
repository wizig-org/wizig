//! Swift API class prelude renderer (init, validation, helper calls).
//!
//! All C symbols are resolved at link time via `import WizigFFI` — no
//! dlopen/dlsym indirection.

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

pub fn appendApiClassCore(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
    _ = methods;
    try out.appendSlice(arena, "public final class WizigGeneratedApi {\n");
    try out.appendSlice(arena, "    public weak var sink: WizigGeneratedEventSink?\n\n");
    try out.appendSlice(arena, "    public init(sink: WizigGeneratedEventSink? = nil) throws {\n");
    try out.appendSlice(arena, "        self.sink = sink\n");
    try out.appendSlice(arena, "        try validateBindings()\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func validateBindings() throws {\n");
    try out.appendSlice(arena, "        let actualAbi = wizig_ffi_abi_version()\n");
    try out.appendSlice(arena, "        let hashPtr = wizig_ffi_contract_hash_ptr()\n");
    try out.appendSlice(arena, "        let hashLen = wizig_ffi_contract_hash_len()\n");
    try out.appendSlice(arena, "        let actualContractHash = hashLen > 0 ? String(bytes: UnsafeBufferPointer(start: hashPtr, count: hashLen), encoding: .utf8) ?? \"\" : \"\"\n");
    try out.appendSlice(arena, "        guard actualAbi == wizigExpectedAbiVersion, actualContractHash == wizigExpectedContractHash else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.compatibilityMismatch(\n");
    try out.appendSlice(arena, "                expectedAbi: wizigExpectedAbiVersion,\n");
    try out.appendSlice(arena, "                actualAbi: actualAbi,\n");
    try out.appendSlice(arena, "                expectedContractHash: wizigExpectedContractHash,\n");
    try out.appendSlice(arena, "                actualContractHash: actualContractHash\n");
    try out.appendSlice(arena, "            )\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func readLastError() -> (domain: String, code: Int32, message: String) {\n");
    try out.appendSlice(arena, "        let domainPtr = wizig_ffi_last_error_domain_ptr()\n");
    try out.appendSlice(arena, "        let domainLen = wizig_ffi_last_error_domain_len()\n");
    try out.appendSlice(arena, "        let domain = domainLen > 0 ? String(bytes: UnsafeBufferPointer(start: domainPtr, count: domainLen), encoding: .utf8) ?? \"\" : \"\"\n");
    try out.appendSlice(arena, "        let code = wizig_ffi_last_error_code()\n");
    try out.appendSlice(arena, "        let msgPtr = wizig_ffi_last_error_message_ptr()\n");
    try out.appendSlice(arena, "        let msgLen = wizig_ffi_last_error_message_len()\n");
    try out.appendSlice(arena, "        let message = msgLen > 0 ? String(bytes: UnsafeBufferPointer(start: msgPtr, count: msgLen), encoding: .utf8) ?? \"\" : \"\"\n");
    try out.appendSlice(arena, "        return (domain, code, message)\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func ensureStatus(_ status: Int32, function: String) throws {\n");
    try out.appendSlice(arena, "        guard status == WizigGeneratedStatus.ok.rawValue else {\n");
    try out.appendSlice(arena, "            let detail = readLastError()\n");
    try out.appendSlice(arena, "            let resolvedCode = detail.code == 0 ? status : detail.code\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.ffiCallFailed(function: function, domain: detail.domain, code: resolvedCode, message: detail.message)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func withUTF8Pointer<T>(_ value: String, _ body: (UnsafePointer<UInt8>, Int) throws -> T) throws -> T {\n");
    try out.appendSlice(arena, "        let bytes = Array(value.utf8)\n");
    try out.appendSlice(arena, "        if bytes.isEmpty {\n");
    try out.appendSlice(arena, "            var placeholder: UInt8 = 0\n");
    try out.appendSlice(arena, "            return try withUnsafePointer(to: &placeholder) { ptr in\n");
    try out.appendSlice(arena, "                try body(ptr, 0)\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return try bytes.withUnsafeBufferPointer { buffer in\n");
    try out.appendSlice(arena, "            try body(buffer.baseAddress!, buffer.count)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");

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
    try out.appendSlice(arena, "        let data = Data(bytes: outPtr, count: outLen)\n");
    try out.appendSlice(arena, "        guard let value = String(data: data, encoding: .utf8) else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.invalidUtf8(function: function)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return value\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func callIntOutput(function: String, _ invoke: (UnsafeMutablePointer<Int64>) -> Int32) throws -> Int64 {\n");
    try out.appendSlice(arena, "        var out: Int64 = 0\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(&out), function: function)\n");
    try out.appendSlice(arena, "        return out\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func callBoolOutput(function: String, _ invoke: (UnsafeMutablePointer<UInt8>) -> Int32) throws -> Bool {\n");
    try out.appendSlice(arena, "        var out: UInt8 = 0\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(&out), function: function)\n");
    try out.appendSlice(arena, "        return out != 0\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func callEnumOutput<T: RawRepresentable>(function: String, _ invoke: (UnsafeMutablePointer<Int64>) -> Int32) throws -> T where T.RawValue == Int64 {\n");
    try out.appendSlice(arena, "        let raw = try callIntOutput(function: function, invoke)\n");
    try out.appendSlice(arena, "        guard let value = T(rawValue: raw) else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.invalidEnumRawValue(function: function, rawValue: raw, typeName: String(describing: T.self))\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return value\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func callStructOutput<T: Decodable>(function: String, _ invoke: (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, UnsafeMutablePointer<Int>) -> Int32) throws -> T {\n");
    try out.appendSlice(arena, "        let json = try callStringOutput(function: function, invoke)\n");
    try out.appendSlice(arena, "        return try JSONDecoder().decode(T.self, from: Data(json.utf8))\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func encodeStructInput<T: Encodable>(_ value: T, function: String) throws -> String {\n");
    try out.appendSlice(arena, "        let data = try JSONEncoder().encode(value)\n");
    try out.appendSlice(arena, "        guard let json = String(data: data, encoding: .utf8) else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.invalidUtf8(function: function)\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        return json\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func callVoidOutput(function: String, _ invoke: () -> Int32) throws {\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(), function: function)\n");
    try out.appendSlice(arena, "    }\n\n");
}
