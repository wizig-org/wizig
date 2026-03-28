# `cli/src/run/platform/ios_discovery/simulator.zig`

_Language: Zig_

iOS simulator discovery and JSON parsing helpers.

## Public API

### `discoverIosDevices` (fn)

Lists available iOS simulators from `simctl`.

```zig
pub fn discoverIosDevices(arena: std.mem.Allocator, io: std.Io, stderr: *Io.Writer) ![]types.IosDevice {
```

### `parseSimulatorDevices` (fn)

Parses the `simctl` devices object into sorted iOS simulator models.

```zig
pub fn parseSimulatorDevices(
    arena: std.mem.Allocator,
    devices_object: std.json.ObjectMap,
) ![]types.IosDevice {
```
