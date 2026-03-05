# `cli/src/run/platform/android_jni_bridge_migration.zig`

_Language: Zig_

Android JNI bridge compatibility migration for Zig print forwarding.

## Problem
Generated JNI bridge files historically did not forward native
`stdout`/`stderr` to Android logcat. As a result, `std.debug.print` output
from Zig code was often invisible during `wizig run` log monitoring.

## Scope
This migration patches `.wizig/generated/android/jni/WizigGeneratedApiBridge.c`
in-place when needed:
- adds Android-only headers (`android/log.h`, `pthread.h`, `unistd.h`)
- injects a one-time stdio-to-logcat forwarder helper
- calls the helper during binding validation

## Safety
Rewrites are idempotent and limited to known generated anchors. User host
sources are not modified.

## Public API

### `MigrationSummary` (const)

Result metadata for generated JNI bridge migration.

```zig
pub const MigrationSummary = struct {
```

### `ensureGeneratedJniBridgeCompatibility` (fn)

Ensures generated Android JNI bridge supports native stdio forwarding.

```zig
pub fn ensureGeneratedJniBridgeCompatibility(
    arena: std.mem.Allocator,
    io: std.Io,
    project_dir: []const u8,
) !MigrationSummary {
```
