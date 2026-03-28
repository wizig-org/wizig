# `src/cli/commands/codegen/project/paths.zig`

_Language: Zig_

Generated output path discovery and optional SDK mirror targets.

## Public API

### `resolveIosMirrorSwiftFile` (fn)

Returns the Swift mirror path for the lexicographically first top-level
`.xcodeproj` under `ios/`.

Multi-project repos can contain several host projects under `ios/`. This
resolver ignores nested `.xcodeproj` directories and selects the first
top-level match in sorted order so the mirror target is stable across
filesystem walk order.

```zig
pub fn resolveIosMirrorSwiftFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
```

### `resolveSdkSwiftApiFile` (fn)

No declaration docs available.

```zig
pub fn resolveSdkSwiftApiFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
```

### `resolveSdkIosRuntimeFile` (fn)

No declaration docs available.

```zig
pub fn resolveSdkIosRuntimeFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
```

### `resolveBundledIosRuntimeSource` (fn)

No declaration docs available.

```zig
pub fn resolveBundledIosRuntimeSource(
    arena: std.mem.Allocator,
    io: std.Io,
) !?[]const u8 {
```

### `resolveSdkIosFfiIncludeDir` (fn)

Returns the SDK iOS WizigFFI include directory for C header mirroring.

```zig
pub fn resolveSdkIosFfiIncludeDir(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
```

### `resolveSdkIosFfiStubSource` (fn)

Returns the SDK iOS WizigFFI C shim file path when present.

```zig
pub fn resolveSdkIosFfiStubSource(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
```

### `resolveSdkKotlinApiFile` (fn)

No declaration docs available.

```zig
pub fn resolveSdkKotlinApiFile(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !?[]const u8 {
```
