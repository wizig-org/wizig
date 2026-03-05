# `cli/src/run/platform/ios_discovery.zig`

_Language: Zig_

iOS simulator and physical device discovery and selection utilities.

This module handles simulator enumeration, physical device discovery,
scheme destination filtering, selector matching, and interactive target
selection for iOS runs.

## Public API

### `discoverIosDevices` (fn)

Lists available iOS simulators from `simctl`.

```zig
pub fn discoverIosDevices(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]types.IosDevice {
```

### `discoverIosSupportedDestinationIds` (fn)

Returns iOS simulator IDs supported by the given Xcode scheme.

```zig
pub fn discoverIosSupportedDestinationIds(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_dir: []const u8,
    xcode_project: []const u8,
    scheme: []const u8,
) ![]const []const u8 {
```

### `discoverIosPhysicalDevices` (fn)

Lists connected physical iOS devices via `xcrun devicectl`.

```zig
pub fn discoverIosPhysicalDevices(arena: std.mem.Allocator, io: std.Io) ![]types.IosDevice {
```

### `filterIosDevicesBySupportedIds` (fn)

Filters discovered iOS devices by allowed destination IDs.

```zig
pub fn filterIosDevicesBySupportedIds(
    arena: std.mem.Allocator,
    devices: []const types.IosDevice,
    supported_ids: []const []const u8,
) ![]types.IosDevice {
```

### `chooseIosDevice` (fn)

Resolves concrete iOS device from selector/prompt.

```zig
pub fn chooseIosDevice(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    devices: []const types.IosDevice,
    selector: ?[]const u8,
    non_interactive: bool,
) !types.IosDevice {
```
