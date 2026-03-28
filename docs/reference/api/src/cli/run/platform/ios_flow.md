# `src/cli/run/platform/ios_flow.zig`

_Language: Zig_

iOS platform run orchestration.

This module owns the public `wizig run ios` entrypoint and delegates target
discovery plus simulator/device launch details to smaller internal modules.

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
