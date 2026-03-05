# `cli/src/commands/codegen/contract/parse_shared.zig`

_Language: Zig_

Shared parsing helpers used by Zig and JSON contract parsers.

## Public API

### `parseTypeTokenWithKnown` (fn)

Resolves a type token to an API type.

## Accepted Tokens
- primitive aliases: `string`, `int`, `bool`, `void`
- discovered type names from `known_struct_names` / `known_enum_names`

```zig
pub fn parseTypeTokenWithKnown(
    token_raw: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) !api.ApiType {
```

### `dupRequiredString` (fn)

Duplicates a required non-empty JSON string field.

```zig
pub fn dupRequiredString(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    field: []const u8,
) ![]u8 {
```
