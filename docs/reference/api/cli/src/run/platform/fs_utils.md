# `cli/src/run/platform/fs_utils.zig`

_Language: Zig_

Filesystem utility helpers for run/platform modules.

This file centralizes path and file mutation helpers so the iOS/Android
runners can focus on orchestration logic instead of repeated I/O boilerplate.

## Public API

### `joinPath` (fn)

Joins a base path and child segment using the host separator.

```zig
pub fn joinPath(allocator: Allocator, base: []const u8, name: []const u8) ![]u8 {
```

### `pathExists` (fn)

Returns whether a path exists from the current working directory.

```zig
pub fn pathExists(io: std.Io, path: []const u8) bool {
```

### `writeFileAtomically` (fn)

Writes a file atomically with parent path creation.

```zig
pub fn writeFileAtomically(io: std.Io, path: []const u8, contents: []const u8) !void {
```

### `copyFileIfChanged` (fn)

Copies a file only when destination content differs.

```zig
pub fn copyFileIfChanged(
    arena: Allocator,
    io: std.Io,
    src_path: []const u8,
    dst_path: []const u8,
) !void {
```
