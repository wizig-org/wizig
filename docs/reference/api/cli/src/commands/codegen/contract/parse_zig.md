# `cli/src/commands/codegen/contract/parse_zig.zig`

_Language: Zig_

Zig contract parser (`wizig.api.zig`).

## Supported Shape
- `pub const namespace = "...";`
- `pub const methods = .{ .{ ... }, ... };`
- `pub const events = .{ .{ ... }, ... };`
- `pub const structs = .{ .{ .name, .fields = .{ ... } }, ... };`
- `pub const enums = .{ .{ .name, .variants = .{ ... } }, ... };`

## Public API

### `parseApiSpecFromZig` (fn)

Parses a Zig contract into `ApiSpec`.

```zig
pub fn parseApiSpecFromZig(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
```
