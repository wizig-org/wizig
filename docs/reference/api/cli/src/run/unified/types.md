# `cli/src/run/unified/types.zig`

_Language: Zig_

Domain types for unified run orchestration.

These types represent normalized unified run options and discovered platform
candidates before delegation into platform-specific execution.

## Public API

### `Platform` (const)

Platform label used by unified candidate records.

```zig
pub const Platform = enum {
```

### `UnifiedOptions` (const)

Parsed options for `wizig run` unified mode.

```zig
pub const UnifiedOptions = struct {
```

### `Candidate` (const)

Candidate target selected from iOS/Android discovery results.

```zig
pub const Candidate = struct {
```

### `DeviceInfo` (const)

Generic device record used during discovery before candidate conversion.

```zig
pub const DeviceInfo = struct {
```

### `platformLabel` (fn)

Converts platform enum to a stable CLI label.

```zig
pub fn platformLabel(platform: Platform) []const u8 {
```

### `lessDeviceInfo` (fn)

Sort comparator for case-insensitive device name ordering.

```zig
pub fn lessDeviceInfo(_: void, a: DeviceInfo, b: DeviceInfo) bool {
```
