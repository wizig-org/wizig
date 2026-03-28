# `cli/src/run/platform/android_discovery/emulator.zig`

_Language: Zig_

Android emulator start and wait helpers.

## Public API

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

### `selectNewEmulatorDevice` (fn)

Picks the first newly discovered emulator device that is not already known.

```zig
pub fn selectNewEmulatorDevice(
    allocator: std.mem.Allocator,
    existing_devices: []const types.AndroidDevice,
    discovered_devices: []const types.AndroidDevice,
) !?types.AndroidDevice {
```
