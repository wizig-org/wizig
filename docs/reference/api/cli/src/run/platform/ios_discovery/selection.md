# `cli/src/run/platform/ios_discovery/selection.zig`

_Language: Zig_

iOS discovery selection and filtering helpers.

## Public API

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

Resolves concrete iOS device from selector or interactive prompt.

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
