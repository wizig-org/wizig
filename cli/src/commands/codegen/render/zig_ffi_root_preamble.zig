//! Shared preamble emitted before generated FFI method exports.

const std = @import("std");

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

    try out.appendSlice(arena, "const bootstrap_allocator = std.heap.page_allocator;\n\n");
    try out.appendSlice(arena, "pub const WizigRuntimeHandle = opaque {};\n\n");
    try out.appendSlice(arena, "const RuntimeBox = struct {\n");
    try out.appendSlice(arena, "    app_name: []u8,\n");
    try out.appendSlice(arena, "    gpa: std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }),\n");
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

    try out.appendSlice(arena, "pub export fn wizig_ffi_abi_version() u32 {\n");
    try out.appendSlice(arena, "    return wizig_generated_abi_version;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_contract_hash_ptr() [*]const u8 {\n");
    try out.appendSlice(arena, "    return wizig_generated_contract_hash.ptr;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_ffi_contract_hash_len() usize {\n");
    try out.appendSlice(arena, "    return wizig_generated_contract_hash.len;\n");
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

    try out.appendSlice(arena, "pub export fn wizig_runtime_new(app_name_ptr: [*]const u8, app_name_len: usize, out_handle: ?*?*WizigRuntimeHandle) i32 {\n");
    try out.appendSlice(arena, "    if (out_handle == null) return setLastError(.argument, statusCode(.null_argument), \"null out_handle\");\n");
    try out.appendSlice(arena, "    const output = out_handle.?;\n");
    try out.appendSlice(arena, "    output.* = null;\n");
    try out.appendSlice(arena, "    if (app_name_len == 0) return setLastError(.argument, statusCode(.invalid_argument), \"empty app name\");\n");
    try out.appendSlice(arena, "    const app_name = app_name_ptr[0..app_name_len];\n");
    try out.appendSlice(arena, "    const box = bootstrap_allocator.create(RuntimeBox) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
    try out.appendSlice(arena, "    errdefer bootstrap_allocator.destroy(box);\n");
    try out.appendSlice(arena, "    box.gpa = .init;\n");
    try out.appendSlice(arena, "    const gpa_allocator = box.gpa.allocator();\n");
    try out.appendSlice(arena, "    const owned_app_name = gpa_allocator.dupe(u8, app_name) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
    try out.appendSlice(arena, "    box.app_name = owned_app_name;\n");
    try out.appendSlice(arena, "    output.* = toHandle(box);\n");
    try out.appendSlice(arena, "    clearLastError();\n");
    try out.appendSlice(arena, "    return statusCode(.ok);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_runtime_free(handle: ?*WizigRuntimeHandle) void {\n");
    try out.appendSlice(arena, "    if (handle == null) return;\n");
    try out.appendSlice(arena, "    const box = toBox(handle.?);\n");
    try out.appendSlice(arena, "    box.gpa.allocator().free(box.app_name);\n");
    try out.appendSlice(arena, "    _ = box.gpa.deinit();\n");
    try out.appendSlice(arena, "    bootstrap_allocator.destroy(box);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_runtime_echo(handle: ?*WizigRuntimeHandle, input_ptr: [*]const u8, input_len: usize, out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {\n");
    try out.appendSlice(arena, "    if (handle == null or out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
    try out.appendSlice(arena, "    output_ptr.* = null;\n");
    try out.appendSlice(arena, "    output_len.* = 0;\n");
    try out.appendSlice(arena, "    const box = toBox(handle.?);\n");
    try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
    try out.appendSlice(arena, "    const echoed = std.fmt.allocPrint(bootstrap_allocator, \"{s}:{s}\", .{ box.app_name, input }) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
    try out.appendSlice(arena, "    output_ptr.* = echoed.ptr;\n");
    try out.appendSlice(arena, "    output_len.* = echoed.len;\n");
    try out.appendSlice(arena, "    clearLastError();\n");
    try out.appendSlice(arena, "    return statusCode(.ok);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_bytes_free(ptr: ?[*]u8, len: usize) void {\n");
    try out.appendSlice(arena, "    if (ptr == null) return;\n");
    try out.appendSlice(arena, "    bootstrap_allocator.free(ptr.?[0..len]);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn mapError(err: anyerror) i32 {\n");
    try out.appendSlice(arena, "    return switch (err) {\n");
    try out.appendSlice(arena, "        error.OutOfMemory => setLastError(.memory, statusCode(.out_of_memory), \"out of memory\"),\n");
    try out.appendSlice(arena, "        else => setLastError(.runtime, statusCode(.internal_error), @errorName(err)),\n");
    try out.appendSlice(arena, "    };\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn Unwrapped(comptime T: type) type {\n");
    try out.appendSlice(arena, "    return switch (@typeInfo(T)) {\n");
    try out.appendSlice(arena, "        .error_union => |info| info.payload,\n");
    try out.appendSlice(arena, "        else => T,\n");
    try out.appendSlice(arena, "    };\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn unwrapResult(value: anytype) !Unwrapped(@TypeOf(value)) {\n");
    try out.appendSlice(arena, "    return switch (@typeInfo(@TypeOf(value))) {\n");
    try out.appendSlice(arena, "        .error_union => value,\n");
    try out.appendSlice(arena, "        else => value,\n");
    try out.appendSlice(arena, "    };\n");
    try out.appendSlice(arena, "}\n\n");
}
