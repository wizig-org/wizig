# `src/cli/commands/codegen/render/android_jni/method_call_inputs.zig`

_Language: Zig_

## Public API

### `appendMethodBody` (fn)

No declaration docs available.

```zig
pub fn appendMethodBody(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    ffi_name: []const u8,
    method: api.ApiMethod,
) !void {
```
