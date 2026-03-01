# `cli/src/run/platform/android_discovery.zig`

_Language: Zig_

Android device and AVD discovery/selection helpers.

This module provides enumeration and selection behavior for connected devices
and emulator profiles, including AVD boot and adb visibility waits.

## Public API

### `discoverAndroidDevices` (fn)

Discovers connected Android devices via `adb devices -l`.

```zig
pub fn discoverAndroidDevices(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]types.AndroidDevice {
```

### `discoverAndroidAvds` (fn)

Discovers available Android Virtual Device profile names.

```zig
pub fn discoverAndroidAvds(arena: std.mem.Allocator, io: std.Io) ![]const []const u8 {
```

### `chooseAndroidTarget` (fn)

Resolves Android target from selector or interactive prompt.

```zig
pub fn chooseAndroidTarget(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    devices: []const types.AndroidDevice,
    avds: []const []const u8,
    selector_raw: ?[]const u8,
    non_interactive: bool,
) !types.AndroidTarget {
```

### `startAvd` (fn)

Starts an AVD profile in detached emulator process.

```zig
pub fn startAvd(io: std.Io, stderr: *Io.Writer, avd_name: []const u8) !void {
```

### `waitForStartedEmulator` (fn)

Waits until a newly-started AVD appears in `adb devices`.

```zig
pub fn waitForStartedEmulator(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    existing_devices: []const types.AndroidDevice,
    avd_name: []const u8,
) !types.AndroidDevice {
```
