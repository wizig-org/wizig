# `src/cli/run/platform/android_flow/build.zig`

_Language: Zig_

Android Gradle build preparation and APK discovery.

This module owns the host-managed FFI Gradle setup so the main flow can
stay focused on orchestration.

## Public API

### `AndroidBuildState` (const)

Prepared Android build inputs and environment state.

```zig
pub const AndroidBuildState = struct {
```

### `prepareAndroidBuild` (fn)

Prepares Gradle environment, runs compatibility migrations, and resolves build inputs.

```zig
pub fn prepareAndroidBuild(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_dir: []const u8,
    module: []const u8,
    ffi_plan: android_build_plan.HostManagedAndroidFfiPlan,
) !AndroidBuildState {
```

### `runAndroidBuild` (fn)

Builds the Android app and returns the debug APK path.

```zig
pub fn runAndroidBuild(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_dir: []const u8,
    module: []const u8,
    state: AndroidBuildState,
) ![]const u8 {
```

### `selectGradleCommand` (fn)

Selects the Gradle wrapper when both the script and jar are available.

```zig
pub fn selectGradleCommand(has_wrapper_script: bool, has_wrapper_jar: bool) []const u8 {
```
