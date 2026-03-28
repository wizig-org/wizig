# `cli/src/run/platform/ios_ffi.zig`

_Language: Zig_

iOS FFI build and bundling support for simulators and real devices.

This facade keeps the long-lived public API stable while delegating the
implementation to focused submodules under `ios_ffi/`.

## Public API

### `BundleResult` (const)

Detailed result for embedding the framework into an app bundle.

```zig
pub const BundleResult = bundle.BundleResult;
```

### `buildIosSimulatorFfiLibrary` (fn)

Builds or reuses the cached iOS simulator FFI framework binary.

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

Builds or reuses the cached iOS device FFI framework binary.

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

Copies a host framework into a device app bundle and signs it when needed.

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

### `bundleIosFfiLibraryForDeviceDetailed` (fn)

Copies a host framework into a device app bundle and reports whether it changed.

```zig
pub fn bundleIosFfiLibraryForDeviceDetailed(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
    sign_identity: ?[]const u8,
) !BundleResult {
```

### `bundleIosFfiLibraryForSimulator` (fn)

Copies a host framework into a simulator app bundle.

Destination files are only rewritten when the bytes differ.

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

Resolves an existing iOS FFI library path from the environment or `zig-out`.

```zig
pub fn resolveIosFfiLibraryPath(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
) !?[]const u8 {
```
