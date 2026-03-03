# `cli/src/run/platform/ios_ffi.zig`

_Language: Zig_

iOS simulator FFI build and bundling support.

This module builds cached simulator framework binaries and installs
`WizigFFI.framework` into app bundle locations expected by runtime loaders.

## Public API

### `buildIosSimulatorFfiLibrary` (fn)

Builds or reuses cached iOS simulator FFI framework binary for the current app.

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

Copies host framework into simulator app `Frameworks` location.

## Incrementality
Destination files are updated only when bytes differ, preserving filesystem
metadata via `cp` while avoiding redundant writes.

## Launch Stability
On modern simulator runtimes, placing unmanaged dynamic libraries directly in
app roots can fail installation preflight. This function stages the runtime
as `WizigFFI.framework` and re-signs changed artifacts to satisfy launch
policy checks.

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
