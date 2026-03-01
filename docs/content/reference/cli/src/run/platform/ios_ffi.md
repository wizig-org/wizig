# `cli/src/run/platform/ios_ffi.zig`

_Language: Zig_

iOS simulator FFI build and bundling support.

This module builds cached simulator dylibs and installs them into app bundle
locations expected by simulator launch environment variables.

## Public API

### `buildIosSimulatorFfiLibrary` (fn)

Builds or reuses cached iOS simulator FFI dylib for the current app.

```zig
pub fn buildIosSimulatorFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
```

### `bundleIosFfiLibraryForSimulator` (fn)

Copies host dylib into simulator bundle and framework locations.

```zig
pub fn bundleIosFfiLibraryForSimulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) ![]const u8 {
```

### `resolveIosFfiLibraryPath` (fn)

Resolves existing iOS FFI library path from environment or default output.

```zig
pub fn resolveIosFfiLibraryPath(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
) !?[]const u8 {
```
