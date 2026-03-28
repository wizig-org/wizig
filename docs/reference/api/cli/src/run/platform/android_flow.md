# `cli/src/run/platform/android_flow.zig`

_Language: Zig_

Android platform run orchestration.

This facade keeps the public entrypoint stable while delegating the Android
run pipeline to smaller stage-specific modules.

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
    options: @import("types.zig").RunOptions,
) !void {
```
