# `cli/src/commands/codegen/project/type_discovery_parse.zig`

_Language: Zig_

Parsing helpers for user type discovery.

## Scope
- Extract public `struct`/`enum` declarations from Zig source text.
- Parse struct fields and enum variants into `ApiSpec` model types.
- Resolve field type tokens using known discovered type-name registries.

## Public API

### `ParsedTypeNames` (const)

Lightweight list of discovered type names from one source file.

```zig
pub const ParsedTypeNames = struct {
```

### `collectTypeNamesFromSource` (fn)

Collects top-level `pub const <Name> = struct|enum ...` declarations.

```zig
pub fn collectTypeNamesFromSource(arena: std.mem.Allocator, source: []const u8) !ParsedTypeNames {
```

### `parseStructsFromSource` (fn)

Parses all public struct declarations from `source`.

```zig
pub fn parseStructsFromSource(
    arena: std.mem.Allocator,
    source: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.UserStruct {
```

### `parseEnumsFromSource` (fn)

Parses all public enum declarations from `source`.

```zig
pub fn parseEnumsFromSource(arena: std.mem.Allocator, source: []const u8) ![]const api.UserEnum {
```

### `parseFieldType` (fn)

Resolves a field type token against primitive and discovered type registries.

```zig
pub fn parseFieldType(
    token: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ?api.ApiType {
```
