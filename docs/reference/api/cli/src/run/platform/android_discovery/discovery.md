# `cli/src/run/platform/android_discovery/discovery.zig`

_Language: Zig_

Android adb and AVD discovery helpers.

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

### `parseAndroidDevicesOutput` (fn)

Parses `adb devices -l` output into structured device records.

```zig
pub fn parseAndroidDevicesOutput(arena: std.mem.Allocator, output: []const u8) !std.ArrayList(types.AndroidDevice) {
```

### `parseAvdListFromOutput` (fn)

Parses `emulator -list-avds` output into a sorted list of names.

```zig
pub fn parseAvdListFromOutput(arena: std.mem.Allocator, output: []const u8) ![]const []const u8 {
```
