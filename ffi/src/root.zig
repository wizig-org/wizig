const std = @import("std");
const ziggy_core = @import("ziggy_core");

pub const Status = enum(i32) {
    ok = 0,
    null_argument = 1,
    out_of_memory = 2,
    invalid_argument = 3,
    internal_error = 255,
};

pub const ZiggyRuntimeHandle = opaque {};

const allocator = std.heap.page_allocator;

const RuntimeBox = struct {
    runtime: ziggy_core.Runtime,
};

fn statusCode(status: Status) i32 {
    return @intFromEnum(status);
}

fn toBox(handle: *ZiggyRuntimeHandle) *RuntimeBox {
    return @ptrCast(@alignCast(handle));
}

fn toHandle(box: *RuntimeBox) *ZiggyRuntimeHandle {
    return @ptrCast(box);
}

pub export fn ziggy_runtime_new(
    app_name_ptr: [*]const u8,
    app_name_len: usize,
    out_handle: ?*?*ZiggyRuntimeHandle,
) i32 {
    if (out_handle == null) return statusCode(.null_argument);
    const output = out_handle.?;
    output.* = null;

    if (app_name_len == 0) return statusCode(.invalid_argument);
    const app_name = app_name_ptr[0..app_name_len];

    const box = allocator.create(RuntimeBox) catch return statusCode(.out_of_memory);
    errdefer allocator.destroy(box);

    box.runtime = ziggy_core.Runtime.init(allocator, app_name) catch |err| switch (err) {
        error.OutOfMemory => return statusCode(.out_of_memory),
    };

    output.* = toHandle(box);
    return statusCode(.ok);
}

pub export fn ziggy_runtime_free(handle: ?*ZiggyRuntimeHandle) void {
    if (handle == null) return;

    const box = toBox(handle.?);
    box.runtime.deinit();
    allocator.destroy(box);
}

pub export fn ziggy_runtime_echo(
    handle: ?*ZiggyRuntimeHandle,
    input_ptr: [*]const u8,
    input_len: usize,
    out_ptr: ?*?[*]u8,
    out_len: ?*usize,
) i32 {
    if (handle == null or out_ptr == null or out_len == null) {
        return statusCode(.null_argument);
    }

    const output_ptr = out_ptr.?;
    const output_len = out_len.?;
    output_ptr.* = null;
    output_len.* = 0;

    const box = toBox(handle.?);
    const input = input_ptr[0..input_len];

    const echoed = box.runtime.echo(input, allocator) catch |err| switch (err) {
        error.OutOfMemory => return statusCode(.out_of_memory),
    };

    output_ptr.* = echoed.ptr;
    output_len.* = echoed.len;
    return statusCode(.ok);
}

pub export fn ziggy_bytes_free(ptr: ?[*]u8, len: usize) void {
    if (ptr == null) return;
    allocator.free(ptr.?[0..len]);
}

test "ffi runtime round trip" {
    var handle: ?*ZiggyRuntimeHandle = null;
    try std.testing.expectEqual(statusCode(.ok), ziggy_runtime_new("demo".ptr, "demo".len, &handle));
    defer ziggy_runtime_free(handle);

    var output_ptr: ?[*]u8 = null;
    var output_len: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        ziggy_runtime_echo(handle, "hello".ptr, "hello".len, &output_ptr, &output_len),
    );
    defer ziggy_bytes_free(output_ptr, output_len);

    try std.testing.expect(output_ptr != null);
    try std.testing.expectEqualStrings("demo:hello", output_ptr.?[0..output_len]);
}
