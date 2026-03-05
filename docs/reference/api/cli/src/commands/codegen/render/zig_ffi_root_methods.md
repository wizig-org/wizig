# `cli/src/commands/codegen/render/zig_ffi_root_methods.zig`

_Language: Zig_

Per-method FFI export generation for `WizigGeneratedFfiRoot.zig`.

Wire mapping:
- `user_enum`   <-> `i64` ordinal
- `user_struct` <-> UTF-8 JSON bytes over existing string ABI

## Public API

### `appendMethodExports` (fn)

Appends generated export functions for every discovered API method.

```zig
pub fn appendMethodExports(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
```
