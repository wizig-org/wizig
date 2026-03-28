//! Shared preamble emitted before generated FFI method exports.
//!
//! Emits type definitions, allocator setup, error helpers, and FFI
//! handshake exports (abi version, contract hash, last-error accessors).

const std = @import("std");

/// Appends the FFI prelude: Status/error types, allocator, pointer
/// cast helpers, and all `wizig_ffi_*` handshake exports.
pub fn appendPrelude(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "pub const Status = enum(i32) {\n");
    try out.appendSlice(arena, "    ok = 0,\n");
    try out.appendSlice(arena, "    null_argument = 1,\n");
    try out.appendSlice(arena, "    out_of_memory = 2,\n");
    try out.appendSlice(arena, "    invalid_argument = 3,\n");
    try out.appendSlice(arena, "    internal_error = 255,\n");
    try out.appendSlice(arena, "};\n\n");

    try out.appendSlice(arena, "const ErrorDomain = enum(u32) {\n");
    try out.appendSlice(arena, "    none = 0,\n");
    try out.appendSlice(arena, "    argument = 1,\n");
    try out.appendSlice(arena, "    memory = 2,\n");
    try out.appendSlice(arena, "    runtime = 3,\n");
    try out.appendSlice(arena, "    compatibility = 4,\n");
    try out.appendSlice(arena, "};\n\n");

    try out.appendSlice(arena, "const LastError = struct {\n");
    try out.appendSlice(arena, "    domain: ErrorDomain = .none,\n");
    try out.appendSlice(arena, "    code: i32 = 0,\n");
    try out.appendSlice(arena, "    message: []const u8 = \"ok\",\n");
    try out.appendSlice(arena, "};\n\n");

    try out.appendSlice(arena, "threadlocal var last_error: LastError = .{};\n\n");

    try out.appendSlice(arena, "pub const WizigRuntimeHandle = opaque {};\n\n");
    try out.appendSlice(arena, "const Gpa = if (builtin.mode == .Debug)\n");
    try out.appendSlice(arena, "    std.heap.DebugAllocator(.{ .thread_safe = true })\n");
    try out.appendSlice(arena, "else\n");
    try out.appendSlice(arena, "    ReleaseAllocator;\n\n");
    try out.appendSlice(arena, "const ReleaseAllocator = struct {\n");
    try out.appendSlice(arena, "    pub const init: ReleaseAllocator = .{};\n");
    try out.appendSlice(arena, "    pub fn allocator(_: *ReleaseAllocator) std.mem.Allocator {\n");
    try out.appendSlice(arena, "        return std.heap.smp_allocator;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    pub fn deinit(_: *ReleaseAllocator) std.heap.Check {\n");
    try out.appendSlice(arena, "        return .ok;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "};\n\n");
    try out.appendSlice(arena, "const RuntimeBox = struct {\n");
    try out.appendSlice(arena, "    app_name: []u8,\n");
    try out.appendSlice(arena, "    gpa: Gpa,\n");
    try out.appendSlice(arena, "\n");
    try out.appendSlice(arena, "    fn allocator(self: *RuntimeBox) std.mem.Allocator {\n");
    try out.appendSlice(arena, "        return self.gpa.allocator();\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "};\n\n");

    try out.appendSlice(arena, "fn toBox(handle: *WizigRuntimeHandle) *RuntimeBox {\n");
    try out.appendSlice(arena, "    return @ptrCast(@alignCast(handle));\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn toHandle(box: *RuntimeBox) *WizigRuntimeHandle {\n");
    try out.appendSlice(arena, "    return @ptrCast(box);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn getauxval(_: usize) usize {\n");
    try out.appendSlice(arena, "    return 0;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn statusCode(status: Status) i32 {\n");
    try out.appendSlice(arena, "    return @intFromEnum(status);\n");
    try out.appendSlice(arena, "}\n\n");

    try appendDomainAndErrorHelpers(out, arena);
    try appendFfiHandshakeExports(out, arena);
}

/// Emits domainLabel, setLastError, clearLastError.
fn appendDomainAndErrorHelpers(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "fn domainLabel(domain: ErrorDomain) []const u8 {\n");
    try out.appendSlice(arena, "    return switch (domain) {\n");
    try out.appendSlice(arena, "        .none => \"wizig.ok\",\n");
    try out.appendSlice(arena, "        .argument => \"wizig.argument\",\n");
    try out.appendSlice(arena, "        .memory => \"wizig.memory\",\n");
    try out.appendSlice(arena, "        .runtime => \"wizig.runtime\",\n");
    try out.appendSlice(arena, "        .compatibility => \"wizig.compatibility\",\n");
    try out.appendSlice(arena, "    };\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn setLastError(domain: ErrorDomain, code: i32, message: []const u8) i32 {\n");
    try out.appendSlice(arena, "    last_error = .{ .domain = domain, .code = code, .message = message };\n");
    try out.appendSlice(arena, "    return code;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn clearLastError() void {\n");
    try out.appendSlice(arena, "    last_error = .{};\n");
    try out.appendSlice(arena, "}\n\n");
}

/// Emits wizig_ffi_abi_version, contract hash, wire format version,
/// and last-error accessor exports.
fn appendFfiHandshakeExports(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "pub export fn wizig_ffi_abi_version() u32 {\n");
    try out.appendSlice(arena, "    return wizig_generated_abi_version;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_contract_hash_ptr() [*]const u8 {\n");
    try out.appendSlice(arena, "    return wizig_generated_contract_hash.ptr;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_contract_hash_len() usize {\n");
    try out.appendSlice(arena, "    return wizig_generated_contract_hash.len;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_wire_format_version() u32 {\n");
    try out.appendSlice(arena, "    return wizig_generated_wire_format_version;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_domain_ptr() [*]const u8 {\n");
    try out.appendSlice(arena, "    const label = domainLabel(last_error.domain);\n");
    try out.appendSlice(arena, "    return label.ptr;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_domain_len() usize {\n");
    try out.appendSlice(arena, "    return domainLabel(last_error.domain).len;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_code() i32 {\n");
    try out.appendSlice(arena, "    return last_error.code;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_message_ptr() [*]const u8 {\n");
    try out.appendSlice(arena, "    return last_error.message.ptr;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_last_error_message_len() usize {\n");
    try out.appendSlice(arena, "    return last_error.message.len;\n");
    try out.appendSlice(arena, "}\n\n");
}
