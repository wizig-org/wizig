# `src/cli/commands/codegen/project/type_discovery/registry.zig`

_Language: Zig_

User-type registry assembly for `lib/**/*.zig`.

## Public API

### `TypeRegistry` (const)

Collected user-defined type information discovered from app sources.

```zig
pub const TypeRegistry = struct {
```

### `discoverLibTypes` (fn)

Discovers user structs and enums from `project_root/lib/**/*.zig`.

```zig
pub fn discoverLibTypes(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !TypeRegistry {
```
