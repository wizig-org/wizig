# `cli/src/commands/codegen/contract/parse_json.zig`

_Language: Zig_

JSON contract parser (`wizig.api.json`).

## Public API

### `parseApiSpecFromJson` (fn)

Parses JSON contract text into an `ApiSpec`.

Expected schema:
- `namespace`: string
- `methods`: array of `{ name, input, output }`
- `events`: array of `{ name, payload }`
- `structs` (optional): array of `{ name, fields: [{ name, field_type }] }`
- `enums` (optional): array of `{ name, variants: [string] }`

```zig
pub fn parseApiSpecFromJson(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
```
