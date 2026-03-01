# `cli/src/run/platform/selection.zig`

_Language: Zig_

Interactive and selector-based target resolution utilities.

The run command supports both explicit selectors and guided prompts.
This module encapsulates that UX logic for iOS and Android targets.

## Public API

### `promptSelection` (fn)

Prompts the user for a numeric selection index in the allowed range.

```zig
pub fn promptSelection(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    option_count: usize,
) !usize {
```

### `readTrimmedLine` (fn)

Reads one input line from stdin and trims surrounding whitespace.

```zig
pub fn readTrimmedLine(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
```

### `findIosDeviceBySelector` (fn)

Finds an iOS device by exact UDID or case-insensitive display name.

```zig
pub fn findIosDeviceBySelector(
    devices: []const types.IosDevice,
    selector: []const u8,
) ?types.IosDevice {
```

### `findAndroidDeviceBySelector` (fn)

Finds an Android device by exact serial or case-insensitive model name.

```zig
pub fn findAndroidDeviceBySelector(
    devices: []const types.AndroidDevice,
    selector: []const u8,
) ?types.AndroidDevice {
```

### `findAvdBySelector` (fn)

Finds an AVD profile by normalized selector (`avd:<name>` supported).

```zig
pub fn findAvdBySelector(avds: []const []const u8, selector: []const u8) ?[]const u8 {
```
