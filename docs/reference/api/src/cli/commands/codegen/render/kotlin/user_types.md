# `src/cli/commands/codegen/render/kotlin/user_types.zig`

_Language: Zig_

Kotlin type definition generation for user structs and enums.

Struct serialization uses a compact binary wire format (v1) with
`ByteBuffer` / `ByteArrayOutputStream` instead of JSON, keeping the
Android integration dependency-free.

## Public API

### `appendKotlinTypeDefinitions` (fn)

Appends Kotlin enum/data classes plus binary wire helpers for user types.

```zig
pub fn appendKotlinTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
```
