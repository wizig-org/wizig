# `src/cli/commands/codegen/render/android_jni/method_call_returns.zig`

_Language: Zig_

## Public API

### `appendByteOutputReturn` (fn)

No declaration docs available.

```zig
pub fn appendByteOutputReturn(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
    is_struct_output: bool,
) !void {
```

### `appendIntOutputReturn` (fn)

No declaration docs available.

```zig
pub fn appendIntOutputReturn(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
) !void {
```

### `appendBoolOutputReturn` (fn)

No declaration docs available.

```zig
pub fn appendBoolOutputReturn(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
) !void {
```

### `appendVoidOutputReturn` (fn)

No declaration docs available.

```zig
pub fn appendVoidOutputReturn(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
) !void {
```

### `nullReturnForOutput` (fn)

No declaration docs available.

```zig
pub fn nullReturnForOutput(output_wire: helpers.WireKind) []const u8 {
```
