# `src/cli/commands/codegen/project/lib_discovery.zig`

_Language: Zig_

Discovery of API method signatures and module imports from `lib/**/*.zig`.

## Public API

### `discoverLibApiMethods` (fn)

Discovers public API methods from `lib/**/*.zig` using only built-in type rules.

```zig
pub fn discoverLibApiMethods(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const api.ApiMethod {
```

### `discoverLibApiMethodsWithTypes` (fn)

Discovers public API methods from `lib/**/*.zig`, resolving known struct and enum names.

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

Collects import paths for `lib/**/*.zig` files.

```zig
pub fn collectLibModuleImports(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) ![]const []const u8 {
```
