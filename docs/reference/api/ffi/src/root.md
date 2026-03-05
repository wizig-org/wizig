# `ffi/src/root.zig`

_Language: Zig_

C ABI bridge exposing Wizig runtime functions to native hosts.

## Compatibility Surface
This module exports:
- runtime entrypoints (`wizig_runtime_*`)
- ABI/version handshake symbols (`wizig_ffi_*`)
- structured last-error accessors (`domain/code/message`)

## Error Model
Calls still return stable integer status codes for C ABI compatibility.
Additionally, failures write a structured thread-local error envelope so
higher-level host bindings can surface richer diagnostics.

## Public API

### `Status` (const)

Stable status codes returned by exported FFI functions.

## Contract
- Numeric values are part of the public C ABI.
- Host bindings may treat these as transport-level outcomes.
- Rich diagnostics are available via `wizig_ffi_last_error_*`.

```zig
pub const Status = enum(i32) {
```

### `WizigRuntimeHandle` (const)

Opaque runtime handle used by C/Swift/Kotlin callers.

## Safety
The pointee layout is private to Zig; callers must treat this as an opaque
token and only pass it back to exported Wizig functions.

```zig
pub const WizigRuntimeHandle = opaque {};
```

### `wizig_ffi_abi_version` (export fn)

Returns generated FFI ABI version for host compatibility checks.

## Handshake
Host bridges compare this value against their compiled expectation before
invoking method entrypoints.

```zig
pub export fn wizig_ffi_abi_version() u32 {
```

### `wizig_ffi_contract_hash_ptr` (export fn)

Returns generated contract hash pointer for host compatibility checks.

## Handshake
This hash represents the generated API contract expected by host bindings.

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

## Usage
Read this immediately after a non-`ok` status to retrieve the latest
structured error envelope for the current thread.

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

## Preconditions
- `out_handle` must be non-null.
- `app_name_len` must be greater than zero.

## Postconditions
- On success, writes a non-null handle to `out_handle`.
- On failure, writes null and updates thread-local structured error state.

```zig
pub export fn wizig_runtime_new(
    app_name_ptr: [*]const u8,
    app_name_len: usize,
    out_handle: ?*?*WizigRuntimeHandle,
) i32 {
```

### `wizig_runtime_free` (export fn)

Destroys a runtime handle previously returned by `wizig_runtime_new`.

## Semantics
Passing null is a no-op to simplify host-side cleanup code paths.

```zig
pub export fn wizig_runtime_free(handle: ?*WizigRuntimeHandle) void {
```

### `wizig_runtime_echo` (export fn)

Executes runtime echo and returns an owned UTF-8 byte buffer.

## Ownership
On success, the caller owns `out_ptr[0..out_len]` and must release it with
`wizig_bytes_free`.

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

## Ownership
This function only accepts pointers returned by Wizig allocation paths.

```zig
pub export fn wizig_bytes_free(ptr: ?[*]u8, len: usize) void {
```
