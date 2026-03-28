# `cli/src/commands/codegen/project/type_discovery.zig`

_Language: Zig_

User-type discovery from `lib/**/*.zig`.

This facade keeps the public API stable while delegating filesystem walking
and registry assembly to smaller modules.

## Public API

### `TypeRegistry` (const)

Collected user-defined type information discovered from app sources.

```zig
pub const TypeRegistry = registry.TypeRegistry;
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

### `parseStructsFromSource` (fn)

Convenience wrapper used by parser-focused tests.

```zig
pub fn parseStructsFromSource(arena: std.mem.Allocator, source: []const u8) ![]const api.UserStruct {
```

### `parseEnumsFromSource` (const)

Convenience wrapper used by parser-focused tests.

```zig
pub const parseEnumsFromSource = parse.parseEnumsFromSource;
```

### `parseFieldType` (const)

Field-token resolution helper re-exported for tests and call sites.

```zig
pub const parseFieldType = parse.parseFieldType;
```
