//! Swift API class prelude renderer (init, validation, helper calls).

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

pub fn appendApiClassCore(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
    try out.appendSlice(arena, "public final class WizigGeneratedApi {\n");
    try out.appendSlice(arena, "    public weak var sink: WizigGeneratedEventSink?\n");
    try out.appendSlice(arena, "    private let ffi: WizigGeneratedFFI\n\n");
    try out.appendSlice(arena, "    public init(libraryPath: String? = nil, sink: WizigGeneratedEventSink? = nil) throws {\n");
    try out.appendSlice(arena, "        self.ffi = try WizigGeneratedFFI(libraryPath: libraryPath)\n");
    try out.appendSlice(arena, "        self.sink = sink\n");
    try out.appendSlice(arena, "        try validateBindings()\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func validateBindings() throws {\n");
    try out.appendSlice(arena, "        let requiredSymbols = [\n");
    try out.appendSlice(arena, "            \"wizig_ffi_abi_version\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_contract_hash_ptr\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_contract_hash_len\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_domain_ptr\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_domain_len\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_code\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_message_ptr\",\n");
    try out.appendSlice(arena, "            \"wizig_ffi_last_error_message_len\",\n");
    for (methods) |method| {
        try helpers.appendFmt(out, arena, "            \"wizig_api_{s}\",\n", .{method.name});
    }
    try out.appendSlice(arena, "        ]\n");
    try out.appendSlice(arena, "        for symbol in requiredSymbols {\n");
    try out.appendSlice(arena, "            do {\n");
    try out.appendSlice(arena, "                _ = try ffi.loadSymbol(symbol, as: UnsafeMutableRawPointer.self)\n");
    try out.appendSlice(arena, "            } catch {\n");
    try out.appendSlice(arena, "                throw WizigGeneratedApiError.bindingValidationFailed(\"\\(symbol): \\(error)\")\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "        let actualAbi = ffi.abiVersion()\n");
    try out.appendSlice(arena, "        let actualContractHash = ffi.readContractHash()\n");
    try out.appendSlice(arena, "        guard actualAbi == wizigExpectedAbiVersion, actualContractHash == wizigExpectedContractHash else {\n");
    try out.appendSlice(arena, "            throw WizigGeneratedApiError.compatibilityMismatch(\n");
    try out.appendSlice(arena, "                expectedAbi: wizigExpectedAbiVersion,\n");
    try out.appendSlice(arena, "                actualAbi: actualAbi,\n");
    try out.appendSlice(arena, "                expectedContractHash: wizigExpectedContractHash,\n");
    try out.appendSlice(arena, "                actualContractHash: actualContractHash\n");
    try out.appendSlice(arena, "            )\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n\n");

    try out.appendSlice(arena, "    private func ensureStatus(_ status: Int32, function: String) throws {\n");
    try out.appendSlice(arena, "        guard status == WizigGeneratedStatus.ok.rawValue else {\n");
    try out.appendSlice(arena, "            let detail = ffi.readLastError()\n");
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
    try out.appendSlice(arena, "            ffi.bytesFree(outPtr, outLen)\n");
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

    try out.appendSlice(arena, "    private func callVoidOutput(function: String, _ invoke: () -> Int32) throws {\n");
    try out.appendSlice(arena, "        try ensureStatus(invoke(), function: function)\n");
    try out.appendSlice(arena, "    }\n\n");
}
