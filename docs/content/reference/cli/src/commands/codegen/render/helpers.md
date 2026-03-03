# `cli/src/commands/codegen/render/helpers.zig`

_Language: Zig_

Shared helpers for renderer modules.

## Public API

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
