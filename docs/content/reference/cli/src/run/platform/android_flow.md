# `cli/src/run/platform/android_flow.zig`

_Language: Zig_

Android platform run orchestration.

This module coordinates target selection, FFI prep, Gradle build, install,
launch, and optional debugger/log monitor attachment for Android runs.

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
