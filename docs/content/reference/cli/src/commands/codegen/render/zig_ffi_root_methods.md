# `cli/src/commands/codegen/render/zig_ffi_root_methods.zig`

_Language: Zig_

Per-method FFI export generation for `WizigGeneratedFfiRoot.zig`.

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
