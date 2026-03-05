# `cli/src/commands/codegen/render/zig_ffi_root.zig`

_Language: Zig_

Renderer for generated Zig FFI root module.

## Public API

### `renderZigFfiRoot` (fn)

No declaration docs available.

```zig
pub fn renderZigFfiRoot(
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
    compat: compatibility.Metadata,
) ![]u8 {
```
