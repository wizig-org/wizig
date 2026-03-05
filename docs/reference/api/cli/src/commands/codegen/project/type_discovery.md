# `cli/src/commands/codegen/project/type_discovery.zig`

_Language: Zig_

User-type discovery from `lib/**/*.zig`.

## Responsibilities
- Walk `lib/` and discover all public struct/enum declarations.
- Build a global type-name registry before parsing fields.
- Parse full definitions and reject conflicting duplicates by name.
- Expose registry slices used by method discovery and renderers.

## Public API

### `TypeRegistry` (const)

Collected user-defined type information discovered from app sources.

```zig
pub const TypeRegistry = struct {
```

### `discoverLibTypes` (fn)

Discovers user structs/enums from `project_root/lib/**/*.zig`.

Parsing runs in two passes:
1. collect all type names (for cross-file field references),
2. parse concrete definitions and validate duplicates.

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
