# `cli/src/commands/codegen/project/lib_discovery.zig`

_Language: Zig_

Discovery of API method signatures and module imports from `lib/**/*.zig`.

## Public API

### `discoverLibApiMethods` (fn)

No declaration docs available.

```zig
pub fn discoverLibApiMethods(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const api.ApiMethod {
```

### `discoverLibApiMethodsWithTypes` (fn)

No declaration docs available.

```zig
pub fn discoverLibApiMethodsWithTypes(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.ApiMethod {
```

### `collectLibModuleImports` (fn)

No declaration docs available.

```zig
pub fn collectLibModuleImports(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
```
