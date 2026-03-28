# `src/cli/commands/codegen/project/lib_discovery/files.zig`

_Language: Zig_

Filesystem discovery helpers for `lib/**/*.zig`.

## Public API

### `discoverLibSourcePaths` (fn)

Discovers normalized `lib/**/*.zig` file paths in deterministic order.

```zig
pub fn discoverLibSourcePaths(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
```

### `collectLibModuleImports` (fn)

Collects import paths for `lib/**/*.zig` files.

```zig
pub fn collectLibModuleImports(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
```
