# `cli/src/commands/codegen/render/swift/user_types.zig`

_Language: Zig_

Swift type definition generation for user-defined structs and enums.

## Public API

### `appendSwiftTypeDefinitions` (fn)

No declaration docs available.

```zig
pub fn appendSwiftTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
```
