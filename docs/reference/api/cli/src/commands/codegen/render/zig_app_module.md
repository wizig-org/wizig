# `cli/src/commands/codegen/render/zig_app_module.zig`

_Language: Zig_

Renderer for `lib/WizigGeneratedAppModule.zig`.

## Public API

### `renderZigAppModule` (fn)

No declaration docs available.

```zig
pub fn renderZigAppModule(
    arena: std.mem.Allocator,
    spec: api.ApiSpec,
    module_imports: []const []const u8,
) ![]u8 {
```
