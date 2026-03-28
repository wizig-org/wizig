# `src/ffi/error.zig`

_Language: Zig_

Structured error types and thread-local state for the Wizig FFI layer.

Defines the error envelope model used across all exported FFI functions,
including status codes, error domains, and thread-local error storage.

## Public API

### `Status` (const)

Stable status codes returned by exported FFI functions.

Numeric values are part of the public C ABI.
Host bindings may treat these as transport-level outcomes.
Rich diagnostics are available via `wizig_ffi_last_error_*`.

```zig
pub const Status = enum(i32) {
```

### `ErrorDomain` (const)

Stable symbolic domains for structured errors.

Domains separate broad failure classes so host layers can map them to
platform-native error taxonomies without parsing free-form messages.

```zig
pub const ErrorDomain = enum(u32) {
```

### `LastError` (const)

Thread-local structured error envelope.

The envelope is per-thread and overwritten on each FFI call that updates
error state. Callers should snapshot values immediately after a failure.

```zig
pub const LastError = struct {
```

### `statusCode` (fn)

Converts a `Status` enum to its underlying C ABI integer.

```zig
pub fn statusCode(status: Status) i32 {
```

### `domainLabel` (fn)

Maps an `ErrorDomain` to its canonical string label.

```zig
pub fn domainLabel(domain: ErrorDomain) []const u8 {
```

### `clearLastError` (fn)

Resets the thread-local error envelope to its default (no-error) state.

```zig
pub fn clearLastError() void {
```

### `setLastError` (fn)

Populates the thread-local error envelope and returns `code`.

```zig
pub fn setLastError(domain: ErrorDomain, code: i32, message: []const u8) i32 {
```
