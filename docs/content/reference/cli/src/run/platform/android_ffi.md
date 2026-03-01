# `cli/src/run/platform/android_ffi.zig`

_Language: Zig_

Android FFI build and staging pipeline.

This module builds ABI-specific Wizig FFI shared libraries, caches results
by content fingerprint, and stages artifacts for Android host build usage.

## Public API

### `prepareAndroidFfiLibrary` (fn)

Builds and stages Android FFI library for the selected device ABI.

```zig
pub fn prepareAndroidFfiLibrary(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    app_root: []const u8,
    serial: []const u8,
) !types.AndroidFfiArtifact {
```

### `resolveAndroidDeviceAbi` (fn)

Resolves device ABI using ordered `getprop` probes.

```zig
pub fn resolveAndroidDeviceAbi(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    serial: []const u8,
) ![]const u8 {
```

### `zigTargetForAndroidAbi` (fn)

Maps Android ABI to the corresponding Zig target triple.

```zig
pub fn zigTargetForAndroidAbi(abi: []const u8) ?[]const u8 {
```
