# `runtime/ffi/src/root.zig`

Runtime-packaged C ABI bridge used in generated app projects.

## Public API

### `Status` (const)

Stable status codes returned by exported FFI functions.

```zig
pub const Status = enum(i32) {
```

### `ZiggyRuntimeHandle` (const)

Opaque runtime handle used by C/Swift/Kotlin callers.

```zig
pub const ZiggyRuntimeHandle = opaque {};
```

### `ziggy_runtime_new` (export fn)

Allocates a runtime handle for the provided app name.

```zig
pub export fn ziggy_runtime_new(
    app_name_ptr: [*]const u8,
    app_name_len: usize,
    out_handle: ?*?*ZiggyRuntimeHandle,
) i32 {
```

### `ziggy_runtime_free` (export fn)

Destroys a runtime handle previously returned by `ziggy_runtime_new`.

```zig
pub export fn ziggy_runtime_free(handle: ?*ZiggyRuntimeHandle) void {
```

### `ziggy_runtime_echo` (export fn)

Executes runtime echo and returns an owned UTF-8 byte buffer.

```zig
pub export fn ziggy_runtime_echo(
    handle: ?*ZiggyRuntimeHandle,
    input_ptr: [*]const u8,
    input_len: usize,
    out_ptr: ?*?[*]u8,
    out_len: ?*usize,
) i32 {
```

### `ziggy_bytes_free` (export fn)

Frees buffers returned by Ziggy FFI functions.

```zig
pub export fn ziggy_bytes_free(ptr: ?[*]u8, len: usize) void {
```
