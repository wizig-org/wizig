# `cli/src/commands/codegen/render/android_jni_bridge.zig`

_Language: Zig_

Renderer for generated Android JNI bridge C source.

## Public API

### `renderAndroidJniBridge` (fn)

No declaration docs available.

```zig
pub fn renderAndroidJniBridge(
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
    compat: compatibility.Metadata,
) ![]u8 {
```
