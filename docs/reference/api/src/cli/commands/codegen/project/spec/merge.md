# `src/cli/commands/codegen/project/spec/merge.zig`

_Language: Zig_

API spec merge helpers.

## Public API

### `mergeSpecWithDiscoveredMethods` (fn)

Legacy merge entry-point kept for existing call sites.

```zig
pub fn mergeSpecWithDiscoveredMethods(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered_methods: []const api.ApiMethod,
) !api.ApiSpec {
```

### `mergeSpecWithDiscoveredTypes` (fn)

Merges discovered methods and user-defined types into a base spec.

Conflicts are rejected when a discovered symbol reuses a name with a
different type signature or field/variant layout.

```zig
pub fn mergeSpecWithDiscoveredTypes(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered_methods: []const api.ApiMethod,
    discovered_structs: []const api.UserStruct,
    discovered_enums: []const api.UserEnum,
) !api.ApiSpec {
```
