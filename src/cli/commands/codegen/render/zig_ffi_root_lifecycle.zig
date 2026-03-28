//! Runtime lifecycle functions and wire-format read/write helpers
//! emitted into the generated FFI root module.
//!
//! Covers: `wizig_runtime_new`, `wizig_runtime_free`, `wizig_runtime_echo`,
//! `wizig_bytes_free`, error mapping, result unwrapping, and binary wire
//! format primitives (read/write for u32, i64, bool, string).

const std = @import("std");

/// Appends runtime lifecycle exports, error-mapping utilities, and
/// binary wire format read/write helpers to the generated FFI root.
pub fn appendLifecycle(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try appendRuntimeExports(out, arena);
    try appendErrorAndResultHelpers(out, arena);
    try appendWireReadHelpers(out, arena);
    try appendWireWriteHelpers(out, arena);
}

/// Emits wizig_runtime_new, wizig_runtime_free, wizig_runtime_echo,
/// and wizig_bytes_free exports.
fn appendRuntimeExports(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "pub export fn wizig_runtime_new(app_name_ptr: [*]const u8, app_name_len: usize, out_handle: ?*?*WizigRuntimeHandle) i32 {\n");
    try out.appendSlice(arena, "    if (out_handle == null) return setLastError(.argument, statusCode(.null_argument), \"null out_handle\");\n");
    try out.appendSlice(arena, "    const output = out_handle.?;\n");
    try out.appendSlice(arena, "    output.* = null;\n");
    try out.appendSlice(arena, "    if (app_name_len == 0) return setLastError(.argument, statusCode(.invalid_argument), \"empty app name\");\n");
    try out.appendSlice(arena, "    const app_name = app_name_ptr[0..app_name_len];\n");
    try out.appendSlice(arena, "    const box = std.heap.smp_allocator.create(RuntimeBox) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
    try out.appendSlice(arena, "    errdefer std.heap.smp_allocator.destroy(box);\n");
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
    try out.appendSlice(arena, "    std.heap.smp_allocator.destroy(box);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_runtime_echo(handle: ?*WizigRuntimeHandle, input_ptr: [*]const u8, input_len: usize, out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {\n");
    try out.appendSlice(arena, "    if (handle == null or out_ptr == null or out_len == null) return setLastError(.argument, statusCode(.null_argument), \"null argument\");\n");
    try out.appendSlice(arena, "    const output_ptr = out_ptr.?;\n");
    try out.appendSlice(arena, "    const output_len = out_len.?;\n");
    try out.appendSlice(arena, "    output_ptr.* = null;\n");
    try out.appendSlice(arena, "    output_len.* = 0;\n");
    try out.appendSlice(arena, "    const box = toBox(handle.?);\n");
    try out.appendSlice(arena, "    const input = input_ptr[0..input_len];\n");
    try out.appendSlice(arena, "    const echoed = std.fmt.allocPrint(ffi_output_allocator, \"{s}:{s}\", .{ box.app_name, input }) catch return setLastError(.memory, statusCode(.out_of_memory), \"out of memory\");\n");
    try out.appendSlice(arena, "    output_ptr.* = echoed.ptr;\n");
    try out.appendSlice(arena, "    output_len.* = echoed.len;\n");
    try out.appendSlice(arena, "    clearLastError();\n");
    try out.appendSlice(arena, "    return statusCode(.ok);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "pub export fn wizig_bytes_free(ptr: ?[*]u8, len: usize) void {\n");
    try out.appendSlice(arena, "    if (ptr == null) return;\n");
    try out.appendSlice(arena, "    ffi_output_allocator.free(ptr.?[0..len]);\n");
    try out.appendSlice(arena, "}\n\n");
}

/// Emits mapError, Unwrapped, and unwrapResult helpers.
fn appendErrorAndResultHelpers(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
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

/// Emits wireReadU32, wireReadI64, wireReadBool, wireReadString helpers.
fn appendWireReadHelpers(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "fn wireReadU32(bytes: []const u8, off: *usize) !u32 {\n");
    try out.appendSlice(arena, "    if (off.* + 4 > bytes.len) return error.InvalidArgument;\n");
    try out.appendSlice(arena, "    const val = std.mem.readInt(u32, bytes[off.*..][0..4], .little);\n");
    try out.appendSlice(arena, "    off.* += 4;\n");
    try out.appendSlice(arena, "    return val;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn wireReadI64(bytes: []const u8, off: *usize) !i64 {\n");
    try out.appendSlice(arena, "    if (off.* + 8 > bytes.len) return error.InvalidArgument;\n");
    try out.appendSlice(arena, "    const val = std.mem.readInt(i64, bytes[off.*..][0..8], .little);\n");
    try out.appendSlice(arena, "    off.* += 8;\n");
    try out.appendSlice(arena, "    return val;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn wireReadBool(bytes: []const u8, off: *usize) !bool {\n");
    try out.appendSlice(arena, "    if (off.* + 1 > bytes.len) return error.InvalidArgument;\n");
    try out.appendSlice(arena, "    const val = bytes[off.*] != 0;\n");
    try out.appendSlice(arena, "    off.* += 1;\n");
    try out.appendSlice(arena, "    return val;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn wireReadString(bytes: []const u8, off: *usize) ![]const u8 {\n");
    try out.appendSlice(arena, "    const len = wireReadU32(bytes, off) catch return error.InvalidArgument;\n");
    try out.appendSlice(arena, "    if (off.* + len > bytes.len) return error.InvalidArgument;\n");
    try out.appendSlice(arena, "    const val = bytes[off.*..][0..len];\n");
    try out.appendSlice(arena, "    off.* += len;\n");
    try out.appendSlice(arena, "    return val;\n");
    try out.appendSlice(arena, "}\n\n");
}

/// Emits wireWriteU32, wireWriteI64, wireWriteBool, wireWriteString helpers.
fn appendWireWriteHelpers(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena, "fn wireWriteU32(buf: *std.ArrayList(u8), alloc: std.mem.Allocator, val: u32) !void {\n");
    try out.appendSlice(arena, "    try buf.appendSlice(alloc, &std.mem.toBytes(std.mem.nativeToLittle(u32, val)));\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn wireWriteI64(buf: *std.ArrayList(u8), alloc: std.mem.Allocator, val: i64) !void {\n");
    try out.appendSlice(arena, "    try buf.appendSlice(alloc, &std.mem.toBytes(std.mem.nativeToLittle(i64, val)));\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn wireWriteBool(buf: *std.ArrayList(u8), alloc: std.mem.Allocator, val: bool) !void {\n");
    try out.appendSlice(arena, "    try buf.append(alloc, if (val) @as(u8, 1) else @as(u8, 0));\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "fn wireWriteString(buf: *std.ArrayList(u8), alloc: std.mem.Allocator, val: []const u8) !void {\n");
    try out.appendSlice(arena, "    try wireWriteU32(buf, alloc, @intCast(val.len));\n");
    try out.appendSlice(arena, "    try buf.appendSlice(alloc, val);\n");
    try out.appendSlice(arena, "}\n\n");
}
