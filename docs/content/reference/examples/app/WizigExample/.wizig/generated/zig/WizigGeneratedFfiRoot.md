# `examples/app/WizigExample/.wizig/generated/zig/WizigGeneratedFfiRoot.zig`

_Language: Zig_

## Public API

### `Status` (const)

No declaration docs available.

```zig
pub const Status = enum(i32) {
```

### `WizigRuntimeHandle` (const)

No declaration docs available.

```zig
pub const WizigRuntimeHandle = opaque {};
```

### `getauxval` (export fn)

No declaration docs available.

```zig
pub export fn getauxval(_: usize) usize {
```

### `wizig_ffi_abi_version` (export fn)

No declaration docs available.

```zig
pub export fn wizig_ffi_abi_version() u32 {
```

### `wizig_ffi_contract_hash_ptr` (export fn)

No declaration docs available.

```zig
pub export fn wizig_ffi_contract_hash_ptr() [*]const u8 {
```

### `wizig_ffi_contract_hash_len` (export fn)

No declaration docs available.

```zig
pub export fn wizig_ffi_contract_hash_len() usize {
```

### `wizig_ffi_last_error_domain_ptr` (export fn)

No declaration docs available.

```zig
pub export fn wizig_ffi_last_error_domain_ptr() [*]const u8 {
```

### `wizig_ffi_last_error_domain_len` (export fn)

No declaration docs available.

```zig
pub export fn wizig_ffi_last_error_domain_len() usize {
```

### `wizig_ffi_last_error_code` (export fn)

No declaration docs available.

```zig
pub export fn wizig_ffi_last_error_code() i32 {
```

### `wizig_ffi_last_error_message_ptr` (export fn)

No declaration docs available.

```zig
pub export fn wizig_ffi_last_error_message_ptr() [*]const u8 {
```

### `wizig_ffi_last_error_message_len` (export fn)

No declaration docs available.

```zig
pub export fn wizig_ffi_last_error_message_len() usize {
```

### `wizig_runtime_new` (export fn)

No declaration docs available.

```zig
pub export fn wizig_runtime_new(app_name_ptr: [*]const u8, app_name_len: usize, out_handle: ?*?*WizigRuntimeHandle) i32 {
```

### `wizig_runtime_free` (export fn)

No declaration docs available.

```zig
pub export fn wizig_runtime_free(handle: ?*WizigRuntimeHandle) void {
```

### `wizig_runtime_echo` (export fn)

No declaration docs available.

```zig
pub export fn wizig_runtime_echo(handle: ?*WizigRuntimeHandle, input_ptr: [*]const u8, input_len: usize, out_ptr: ?*?[*]u8, out_len: ?*usize) i32 {
```

### `wizig_bytes_free` (export fn)

No declaration docs available.

```zig
pub export fn wizig_bytes_free(ptr: ?[*]u8, len: usize) void {
```
