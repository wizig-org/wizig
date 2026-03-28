# `cli/src/run/platform/ios_flow/simulator.zig`

_Language: Zig_

iOS simulator build, bundling, and launch flow.

## Public API

### `run` (fn)

Runs the simulator build, install, and launch pipeline.

```zig
pub fn run(ctx: *const context.RunContext, selected: types.IosDevice) !void {
```
