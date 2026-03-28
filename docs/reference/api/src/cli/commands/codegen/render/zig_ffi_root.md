# `src/cli/commands/codegen/render/zig_ffi_root.zig`

_Language: Zig_

Renderer for generated Zig FFI root module.

## Public API

### `renderZigFfiRoot` (fn)

Renders the complete generated Zig FFI root module from an API spec.

```zig
pub fn renderZigFfiRoot(
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
    compat: compatibility.Metadata,
) ![]u8 {
```
