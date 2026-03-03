# `cli/src/commands/codegen/render/kotlin_api.zig`

_Language: Zig_

Renderer for `WizigGeneratedApi.kt`.

## Public API

### `renderKotlinApi` (fn)

No declaration docs available.

```zig
pub fn renderKotlinApi(
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
    compat: compatibility.Metadata,
) ![]u8 {
```
