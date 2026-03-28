# `cli/src/commands/codegen/project/lib_discovery/signature.zig`

_Language: Zig_

Signature parsing and API method discovery for `lib/**/*.zig`.

## Public API

### `discoverLibApiMethodsWithTypes` (fn)

Discovers API methods from `lib/**/*.zig`, resolving known user-defined types.

```zig
pub fn discoverLibApiMethodsWithTypes(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    known_struct_names: []const []const u8,
    known_enum_names: []const []const u8,
) ![]const api.ApiMethod {
```
