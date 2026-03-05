# `cli/src/commands/codegen/render/swift/api_class_core.zig`

_Language: Zig_

Swift API class prelude renderer (init, validation, helper calls).

All C symbols are resolved at link time via `import WizigFFI` — no
dlopen/dlsym indirection.

## Public API

### `appendApiClassCore` (fn)

No declaration docs available.

```zig
pub fn appendApiClassCore(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
```
