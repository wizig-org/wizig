# `cli/src/commands/codegen/project/spec.zig`

_Language: Zig_

Project-level API spec defaults and merge behavior.

## Public API

### `defaultApiSpecForProject` (fn)

No declaration docs available.

```zig
pub fn defaultApiSpecForProject(arena: std.mem.Allocator, project_root: []const u8) !api.ApiSpec {
```

### `mergeSpecWithDiscoveredMethods` (fn)

No declaration docs available.

```zig
pub fn mergeSpecWithDiscoveredMethods(
    arena: std.mem.Allocator,
    base_spec: api.ApiSpec,
    discovered: []const api.ApiMethod,
) !api.ApiSpec {
```
