# `cli/src/run/platform/android_flow/metadata.zig`

_Language: Zig_

Android launch metadata resolution.

This module resolves the application id and launch activity from explicit
options, manifest metadata, and `aapt` output.

## Public API

### `AndroidLaunchMetadata` (const)

Resolved Android launch metadata used for install and launch commands.

```zig
pub const AndroidLaunchMetadata = struct {
```

### `AndroidLaunchHints` (const)

Optional app launch hints.

```zig
pub const AndroidLaunchHints = struct {
```

### `mergeAndroidLaunchHints` (fn)

Merges a primary hint set with fallback values for missing fields.

```zig
pub fn mergeAndroidLaunchHints(primary: AndroidLaunchHints, fallback: AndroidLaunchHints) AndroidLaunchHints {
```

### `resolveAndroidLaunchMetadata` (fn)

Resolves the Android application id and activity used to launch the app.

```zig
pub fn resolveAndroidLaunchMetadata(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    module: []const u8,
    apk: []const u8,
    app_id_hint: ?[]const u8,
    activity_hint: ?[]const u8,
) !AndroidLaunchMetadata {
```
