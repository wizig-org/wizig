# `cli/src/run/platform/ffi_fingerprint.zig`

_Language: Zig_

Fingerprint computation for cached FFI build artifacts.

The run pipeline caches built FFI outputs in `/tmp` based on source content
and target descriptor. This module provides deterministic hashing across core,
generated, and app Zig inputs.

## Public API

### `ios_ffi_cache_version` (const)

Cache key version for iOS simulator FFI artifacts.

```zig
pub const ios_ffi_cache_version = "wizig-ios-ffi-cache-v2";
```

### `android_ffi_cache_version` (const)

Cache key version for Android FFI artifacts.

```zig
pub const android_ffi_cache_version = "wizig-android-ffi-cache-v2";
```

### `computeFfiFingerprint` (fn)

Computes a stable SHA-256 fingerprint for an FFI build input set.

```zig
pub fn computeFfiFingerprint(
    arena: std.mem.Allocator,
    io: std.Io,
    version: []const u8,
    target_descriptor: []const u8,
    root_source: []const u8,
    core_source: []const u8,
    app_fingerprint_roots: []const []const u8,
) ![]const u8 {
```
