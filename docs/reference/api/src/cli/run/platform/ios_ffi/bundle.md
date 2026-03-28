# `src/cli/run/platform/ios_ffi/bundle.zig`

_Language: Zig_

iOS FFI framework embedding helpers.

This module keeps the simulator and device bundle flows aligned while
isolating the filesystem copy and code-signing steps from the build logic.

## Public API

### `BundleResult` (const)

Result returned by the framework bundling helpers.

```zig
pub const BundleResult = struct {
```

### `bundleIosFfiLibraryForDevice` (fn)

Copies a host framework into a device app bundle and signs it when needed.

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

Copies a host framework into a simulator app bundle and re-signs.

```zig
pub fn bundleIosFfiLibraryForSimulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    app_path: []const u8,
    host_ffi_path: []const u8,
) ![]const u8 {
```
