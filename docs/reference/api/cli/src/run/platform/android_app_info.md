# `cli/src/run/platform/android_app_info.zig`

_Language: Zig_

Android APK and manifest metadata resolution helpers.

This module locates built debug APK artifacts and extracts application id /
launch activity details from manifest, Gradle DSL, or `aapt` output.

## Public API

### `AndroidManifestInfo` (const)

Parsed Android manifest metadata used for launch target resolution.

```zig
pub const AndroidManifestInfo = struct {
```

### `findDebugApk` (fn)

Finds a debug APK from standard Gradle outputs/intermediates directories.

```zig
pub fn findDebugApk(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    module: []const u8,
) ![]const u8 {
```

### `parseAndroidManifest` (fn)

Parses manifest and module Gradle files to infer app id/activity.

```zig
pub fn parseAndroidManifest(
    arena: std.mem.Allocator,
    io: std.Io,
    project_dir: []const u8,
    module: []const u8,
) !AndroidManifestInfo {
```

### `parseAaptBadging` (fn)

Parses `aapt dump badging` output into app id/activity fields.

```zig
pub fn parseAaptBadging(output: []const u8, app_id: *?[]const u8, activity: *?[]const u8) void {
```
