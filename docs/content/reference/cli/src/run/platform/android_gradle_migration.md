# `cli/src/run/platform/android_gradle_migration.zig`

_Language: Zig_

Android Gradle file compatibility migrations for host-managed FFI.

This module performs targeted, idempotent migrations over
`<project>/<module>/build.gradle.kts` to keep host-managed FFI tasks
compatible with modern Android Gradle plugin behavior:
- `jniLibs.directories.add(rootProject.file(...))`
- `jniLibs.directories.add(rootProject.file(...).path)`
- `commandLine("zig", ...)` -> `commandLine(discoverWizigZigBinary(), ...)`
- `-OReleaseFast` -> configurable `-O${requestedWizigOptimize}`

## Public API

### `MigrationSummary` (const)

Result metadata describing whether Android Gradle migration touched the file.

```zig
pub const MigrationSummary = struct {
```

### `ensureBuildGradleKtsCompatibility` (fn)

Ensures Android host build file compatibility for current Gradle APIs.

This function is intentionally cheap (`read -> patch -> compare -> write`),
so it can be called on every Android run invocation without measurable
overhead.

```zig
pub fn ensureBuildGradleKtsCompatibility(
    arena: std.mem.Allocator,
    io: std.Io,
    project_dir: []const u8,
    module: []const u8,
) !MigrationSummary {
```
