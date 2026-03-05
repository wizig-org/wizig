# `cli/src/run/platform/ios_flow.zig`

_Language: Zig_

iOS platform run orchestration.

This module coordinates simulator/device selection, host build, FFI bundling,
and launch/debug behavior for `wizig run ios`.  Physical device support uses
`xcrun devicectl` for installation and launch.

## Public API

### `runIos` (fn)

Executes the full iOS run pipeline.

```zig
pub fn runIos(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
) !void {
```
