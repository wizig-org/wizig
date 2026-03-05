# `cli/src/commands/codegen/render/zig_ffi_types.zig`

_Language: Zig_

Zig type alias generation for user-defined structs and enums in FFI root.

## Public API

### `appendUserTypeDefinitions` (fn)

No declaration docs available.

```zig
pub fn appendUserTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
```
