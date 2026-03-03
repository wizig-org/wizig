# `cli/src/commands/codegen/render/android_jni/method_exports.zig`

_Language: Zig_

Per-method Android JNI export generation.

## Public API

### `appendMethodExports` (fn)

No declaration docs available.

```zig
pub fn appendMethodExports(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
```
