# `cli/src/commands/codegen/project/type_discovery/walk.zig`

_Language: Zig_

Filesystem walking for `lib/**/*.zig` discovery.

## Public API

### `discoverLibSourcePaths` (fn)

Discovers relative source paths under `project_root/lib`.

```zig
pub fn discoverLibSourcePaths(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
```
