# `cli/src/commands/codegen/contract/parse.zig`

_Language: Zig_

Contract parser entry points.

This module keeps a small public surface and delegates format-specific
parsing to specialized submodules to keep each implementation focused and
maintainable.

## Public API

### `parseApiSpecFromZig` (fn)

Parses a Zig contract file (`wizig.api.zig`) into an `ApiSpec`.

```zig
pub fn parseApiSpecFromZig(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
```

### `parseApiSpecFromJson` (fn)

Parses a JSON contract file (`wizig.api.json`) into an `ApiSpec`.

```zig
pub fn parseApiSpecFromJson(arena: std.mem.Allocator, text: []const u8) !api.ApiSpec {
```
