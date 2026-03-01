# `cli/src/run/platform/ios_launch.zig`

_Language: Zig_

iOS project/build and app launch helpers.

This module encapsulates Xcode project lookup/regeneration and resilient
simulator launch routines used by the iOS run flow.

## Public API

### `findXcodeProject` (fn)

Finds the `.xcodeproj` directory inside the host iOS project directory.

```zig
pub fn findXcodeProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
) ![]const u8 {
```

### `maybeRegenerateIosProject` (fn)

Regenerates iOS host project with xcodegen when requested and available.

```zig
pub fn maybeRegenerateIosProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_dir: []const u8,
) !void {
```

### `launchIosAppWithRetry` (fn)

Launches iOS app and retries transient simulator launch failures.

```zig
pub fn launchIosAppWithRetry(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    udid: []const u8,
    bundle_id: []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !std.process.RunResult {
```

### `launchIosAppWithConsoleRetry` (fn)

Launches iOS app with attached simulator console pty and transient retries.

```zig
pub fn launchIosAppWithConsoleRetry(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    udid: []const u8,
    bundle_id: []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !void {
```
