# `cli/src/run/platform/ios_discovery/physical.zig`

_Language: Zig_

iOS physical device discovery and JSON parsing helpers.

## Public API

### `discoverIosPhysicalDevices` (fn)

Lists connected physical iOS devices via `xcrun devicectl`.

```zig
pub fn discoverIosPhysicalDevices(arena: std.mem.Allocator, io: std.Io) ![]types.IosDevice {
```

### `parsePhysicalDevices` (fn)

Parses `devicectl` output into physical iOS device models.

```zig
pub fn parsePhysicalDevices(
    arena: std.mem.Allocator,
    root: std.json.Value,
) ![]types.IosDevice {
```
