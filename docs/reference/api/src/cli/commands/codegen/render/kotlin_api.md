# `src/cli/commands/codegen/render/kotlin_api.zig`

_Language: Zig_

Renderer for `WizigGeneratedApi.kt`.

User type wire mapping:
- `user_struct` <-> binary `ByteArray` (wire format v1)
- `user_enum`   <-> `Long` raw value

## Public API

### `renderKotlinApi` (fn)

Renders the generated Kotlin API facade and native bridge declarations.

```zig
pub fn renderKotlinApi(
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
    compat: compatibility.Metadata,
) ![]u8 {
```
