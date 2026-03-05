# `cli/src/commands/codegen/render/android_jni/base_sections.zig`

_Language: Zig_

Shared C/JNI sections emitted before method-specific JNI bridge exports.

## Public API

### `appendBaseSections` (fn)

No declaration docs available.

```zig
pub fn appendBaseSections(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
```
