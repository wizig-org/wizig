# `cli/src/support/path.zig`

_Language: Zig_

Path helpers shared across CLI commands.

## Public API

### `join` (fn)

Joins two path segments with the platform separator.

```zig
pub fn join(allocator: std.mem.Allocator, base: []const u8, name: []const u8) ![]u8 {
```

### `resolveAbsolute` (fn)

Resolves a possibly-relative path into an absolute path.

```zig
pub fn resolveAbsolute(arena: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
```

### `parentDirAlloc` (fn)

Returns parent directory path or "." when no parent exists.

```zig
pub fn parentDirAlloc(arena: std.mem.Allocator, path: []const u8) ![]u8 {
```

### `normalizeSlashes` (fn)

Normalizes path separators to `/`.

```zig
pub fn normalizeSlashes(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
```

### `trimOptionalQuotes` (fn)

Trims optional matching quote characters around a value.

```zig
pub fn trimOptionalQuotes(value: []const u8) []const u8 {
```
