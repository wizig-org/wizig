# `cli/src/commands/codegen/render/kotlin/user_types.zig`

_Language: Zig_

Kotlin type definition generation for user structs and enums.

To keep Android integration dependency-free, struct JSON conversion is
generated with `org.json.JSONObject` helpers instead of external serializers.

## Public API

### `appendKotlinTypeDefinitions` (fn)

Appends Kotlin enum/data classes plus JSON helpers for user types.

```zig
pub fn appendKotlinTypeDefinitions(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    structs: []const api.UserStruct,
    enums: []const api.UserEnum,
) !void {
```
