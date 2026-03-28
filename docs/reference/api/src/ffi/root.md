# `src/ffi/root.zig`

_Language: Zig_

C ABI bridge exposing Wizig runtime functions to native hosts.
Exports `wizig_runtime_*` entrypoints, `wizig_ffi_*` handshake symbols,
and structured last-error accessors with thread-local error envelopes.

## Public API

### `Status` (const)

Re-exported for test access.

```zig
pub const Status = ffi_error.Status;
```

### `WizigRuntimeHandle` (const)

Opaque runtime handle; callers must treat as an opaque token.

```zig
pub const WizigRuntimeHandle = opaque {};
```

### `init` (const)

No declaration docs available.

```zig
    pub const init: ReleaseAllocator = .{};
```

### `allocator` (fn)

No declaration docs available.

```zig
    pub fn allocator(_: *ReleaseAllocator) std.mem.Allocator {
```

### `deinit` (fn)

No declaration docs available.

```zig
    pub fn deinit(_: *ReleaseAllocator) std.heap.Check {
```

### `wizig_ffi_abi_version` (export fn)

Returns generated FFI ABI version for host compatibility checks.

```zig
pub export fn wizig_ffi_abi_version() u32 {
```

### `wizig_ffi_contract_hash_ptr` (export fn)

Returns generated contract hash pointer for host compatibility checks.

```zig
pub export fn wizig_ffi_contract_hash_ptr() [*]const u8 {
```

### `wizig_ffi_contract_hash_len` (export fn)

Returns generated contract hash length for host compatibility checks.

```zig
pub export fn wizig_ffi_contract_hash_len() usize {
```

### `wizig_ffi_last_error_domain_ptr` (export fn)

Returns structured error domain pointer for the current thread.

```zig
pub export fn wizig_ffi_last_error_domain_ptr() [*]const u8 {
```

### `wizig_ffi_last_error_domain_len` (export fn)

Returns structured error domain length for the current thread.

```zig
pub export fn wizig_ffi_last_error_domain_len() usize {
```

### `wizig_ffi_last_error_code` (export fn)

Returns structured error code for the current thread.

```zig
pub export fn wizig_ffi_last_error_code() i32 {
```

### `wizig_ffi_last_error_message_ptr` (export fn)

Returns structured error message pointer for the current thread.

```zig
pub export fn wizig_ffi_last_error_message_ptr() [*]const u8 {
```

### `wizig_ffi_last_error_message_len` (export fn)

Returns structured error message length for the current thread.

```zig
pub export fn wizig_ffi_last_error_message_len() usize {
```

### `wizig_runtime_new` (export fn)

Allocates and initializes a runtime handle for the provided app name.

```zig
pub export fn wizig_runtime_new(
    app_name_ptr: [*]const u8,
    app_name_len: usize,
    out_handle: ?*?*WizigRuntimeHandle,
) i32 {
```

### `wizig_runtime_free` (export fn)

Destroys a runtime handle previously returned by `wizig_runtime_new`.
Passing null is a no-op to simplify host-side cleanup code paths.

```zig
pub export fn wizig_runtime_free(handle: ?*WizigRuntimeHandle) void {
```

### `wizig_runtime_echo` (export fn)

Executes runtime echo and returns an owned UTF-8 byte buffer.
On success, the caller owns `out_ptr[0..out_len]` and must release
it with `wizig_bytes_free`.

```zig
pub export fn wizig_runtime_echo(
    handle: ?*WizigRuntimeHandle,
    input_ptr: [*]const u8,
    input_len: usize,
    out_ptr: ?*?[*]u8,
    out_len: ?*usize,
) i32 {
```

### `wizig_bytes_free` (export fn)

Frees buffers returned by Wizig FFI functions.
Only accepts pointers returned by Wizig allocation paths.

```zig
pub export fn wizig_bytes_free(ptr: ?[*]u8, len: usize) void {
```
