# `cli/src/run/platform/ios_flow/selection.zig`

_Language: Zig_

iOS target discovery and resolution helpers.

## Public API

### `resolveSelectedDevice` (fn)

Resolves the concrete iOS target to launch for a run invocation.

```zig
pub fn resolveSelectedDevice(ctx: *const context.RunContext) !types.IosDevice {
```
