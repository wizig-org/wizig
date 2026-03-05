# `cli/src/run/platform/ios_ffi.zig`

_Language: Zig_

iOS FFI build and bundling support for simulators and real devices.

This module builds cached dynamic framework binaries and installs
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

### `buildIosDeviceFfiLibrary` (fn)

Builds or reuses cached iOS device FFI framework binary for the current app.

```zig
pub fn buildIosDeviceFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) ![]const u8 {
```

### `bundleIosFfiLibraryForDevice` (fn)

Copies host dynamic framework into device app `Frameworks` location.

## Signing
Device installations require embedded frameworks to be code signed with the
same identity used for the app bundle.

```zig
pub fn bundleIosFfiLibraryForDevice(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
    sign_identity: ?[]const u8,
) ![]const u8 {
```

### `bundleIosFfiLibraryForSimulator` (fn)

Copies host dynamic framework into simulator app `Frameworks` location.

## Incrementality
Destination files are updated only when bytes differ, preserving filesystem
metadata via `cp` while avoiding redundant writes.

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
