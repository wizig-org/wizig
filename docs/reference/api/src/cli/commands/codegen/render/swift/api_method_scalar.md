# `src/cli/commands/codegen/render/swift/api_method_scalar.zig`

_Language: Zig_

## Public API

### `appendScalarOutputCall` (fn)

No declaration docs available.

```zig
pub fn appendScalarOutputCall(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    method: api.ApiMethod,
    symbol_name: []const u8,
    input_wire: helpers.WireKind,
    input_is_user_struct: bool,
    input_is_user_enum: bool,
    output_is_user_enum: bool,
) !void {
```
