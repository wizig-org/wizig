# `src/cli/run/platform/ios_ffi/build.zig`

_Language: Zig_

iOS FFI build orchestration helpers.

This module resolves SDK paths, computes cache fingerprints, and invokes
`zig build-lib` for the simulator and device framework variants.

## Public API

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
