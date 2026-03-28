# `src/cli/run/platform/ios_flow/device.zig`

_Language: Zig_

iOS physical device build, signing, and launch flow.

## Public API

### `run` (fn)

Runs the device build, signing, install, and launch pipeline.

```zig
pub fn run(ctx: *const context.RunContext, selected: types.IosDevice) !void {
```
