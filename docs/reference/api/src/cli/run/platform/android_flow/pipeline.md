# `src/cli/run/platform/android_flow/pipeline.zig`

_Language: Zig_

Android run pipeline orchestration.

This module stitches together target selection, build preparation, launch
metadata resolution, and app install/attach handling.

## Public API

### `runAndroid` (fn)

Executes the full Android run pipeline.

```zig
pub fn runAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
) !void {
```
