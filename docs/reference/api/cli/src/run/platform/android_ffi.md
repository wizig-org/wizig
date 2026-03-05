# `cli/src/run/platform/android_ffi.zig`

_Language: Zig_

Android ABI resolution helpers for host-managed FFI builds.

## Ownership Model
Android FFI compilation is orchestrated by Gradle tasks generated in the
app host project. This module is intentionally limited to ABI discovery and
normalization so the CLI can select device-compatible build parameters
without duplicating library compilation paths.

## Responsibilities
- Resolve a connected device ABI via `adb shell getprop`.
- Map Android ABIs to Zig target triples.
- Provide small parsing helpers covered by unit tests.

## Public API

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
