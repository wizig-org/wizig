# `src/cli/commands/codegen/render/swift/user_types.zig`

_Language: Zig_

Swift type definition generation for user-defined structs and enums.

Structs get `toBinary()` and `fromBinary`/`fromBinaryReader` methods for
wire format v1 encoding. Enums use `Int64` raw values (no Codable).

## Public API

### `appendSwiftTypeDefinitions` (fn)

Appends Swift enum and struct definitions including binary wire methods.

```zig
pub fn appendSwiftTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
```
