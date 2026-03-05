# `cli/src/run/platform/android_build_plan.zig`

_Language: Zig_

Host-managed Android FFI build planning utilities.

## Purpose
This module translates a resolved device ABI into normalized Gradle project
properties consumed by Android host build scripts. Keeping this logic in a
dedicated unit keeps `android_flow.zig` focused on orchestration.

## Compatibility Contract
The produced properties are:
- `android.injected.build.abi`: narrows Android packaging/build outputs.
- `wizig.ffi.abi`: narrows Wizig host-managed Zig FFI build tasks.

Unsupported ABI values are rejected early so users get deterministic errors
before invoking Gradle.

## Public API

### `HostManagedAndroidFfiPlan` (const)

Host-side Gradle property plan for Android FFI orchestration.

```zig
pub const HostManagedAndroidFfiPlan = struct {
```

### `planHostManagedAndroidFfiBuild` (fn)

Creates a host-managed Gradle build plan for an Android ABI.

## Errors
Returns `error.InvalidAndroidAbi` when ABI is not in Wizig's supported map.

```zig
pub fn planHostManagedAndroidFfiBuild(
    arena: std.mem.Allocator,
    abi: []const u8,
) !HostManagedAndroidFfiPlan {
```
