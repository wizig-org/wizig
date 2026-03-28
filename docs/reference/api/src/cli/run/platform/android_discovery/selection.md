# `src/cli/run/platform/android_discovery/selection.zig`

_Language: Zig_

Android target selection helpers.

## Public API

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

### `resolveTargetBySelector` (fn)

Resolves a selector string to either a device or an AVD.

```zig
pub fn resolveTargetBySelector(
    devices: []const types.AndroidDevice,
    avds: []const []const u8,
    selector: []const u8,
) ?types.AndroidTarget {
```
