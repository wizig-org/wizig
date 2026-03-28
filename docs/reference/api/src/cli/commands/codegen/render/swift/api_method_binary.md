# `src/cli/commands/codegen/render/swift/api_method_binary.zig`

_Language: Zig_

## Public API

### `appendBinaryOutputCall` (fn)

No declaration docs available.

```zig
pub fn appendBinaryOutputCall(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    method: api.ApiMethod,
    symbol_name: []const u8,
    input_wire: helpers.WireKind,
    input_is_user_struct: bool,
    input_is_user_enum: bool,
) !void {
```
