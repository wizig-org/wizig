# `cli/src/run/platform/android_flow/selection.zig`

_Language: Zig_

Android target discovery and selection.

This module isolates device and AVD selection so the main flow only deals
with the resolved target.

## Public API

### `resolveAndroidTarget` (fn)

Resolves the Android device to run against, including emulator boot.

```zig
pub fn resolveAndroidTarget(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
) !types.AndroidDevice {
```
