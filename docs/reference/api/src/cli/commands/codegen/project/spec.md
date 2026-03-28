# `src/cli/commands/codegen/project/spec.zig`

_Language: Zig_

Project-level API spec facade.

This module keeps the public codegen API stable while delegating default
spec creation and merge logic to smaller focused helpers.

## Public API

### `defaultApiSpecForProject` (fn)

Builds a minimal default API spec for projects with no explicit contract.

```zig
pub fn defaultApiSpecForProject(arena: std.mem.Allocator, project_root: []const u8) !api.ApiSpec {
```

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

```zig
pub fn mergeSpecWithDiscoveredTypes(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered_methods: []const api.ApiMethod,
    discovered_structs: []const api.UserStruct,
    discovered_enums: []const api.UserEnum,
) !api.ApiSpec {
```
