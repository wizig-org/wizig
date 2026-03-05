# `cli/src/commands/codegen/render/helpers.zig`

_Language: Zig_

Shared helpers for renderer modules.

## Public API

### `WireKind` (const)

Logical ABI wire categories used by generated host and bridge code.

```zig
pub const WireKind = enum {
```

### `appendFmt` (fn)

No declaration docs available.

```zig
pub fn appendFmt(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
```

### `zigType` (fn)

No declaration docs available.

```zig
pub fn zigType(value: api.ApiType) []const u8 {
```

### `swiftType` (fn)

No declaration docs available.

```zig
pub fn swiftType(value: api.ApiType) []const u8 {
```

### `kotlinType` (fn)

No declaration docs available.

```zig
pub fn kotlinType(value: api.ApiType) []const u8 {
```

### `jniCType` (fn)

No declaration docs available.

```zig
pub fn jniCType(value: api.ApiType) []const u8 {
```

### `zigDefaultValue` (fn)

No declaration docs available.

```zig
pub fn zigDefaultValue(value: api.ApiType) []const u8 {
```

### `jniEscape` (fn)

No declaration docs available.

```zig
pub fn jniEscape(arena: std.mem.Allocator, input: []const u8) ![]u8 {
```

### `upperCamel` (fn)

No declaration docs available.

```zig
pub fn upperCamel(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
```

### `isScalarType` (fn)

Returns true if the type is a scalar that can use the existing
method codegen paths directly.

```zig
pub fn isScalarType(value: api.ApiType) bool {
```

### `wireKind` (fn)

Maps high-level API type tags to C-ABI transport categories.

```zig
pub fn wireKind(value: api.ApiType) WireKind {
```
