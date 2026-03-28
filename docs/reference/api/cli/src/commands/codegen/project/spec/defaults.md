# `cli/src/commands/codegen/project/spec/defaults.zig`

_Language: Zig_

Default API spec construction helpers.

## Public API

### `defaultApiSpecForProject` (fn)

Builds a minimal default API spec for a project root path.

```zig
pub fn defaultApiSpecForProject(arena: std.mem.Allocator, project_root: []const u8) !api.ApiSpec {
```

### `defaultNamespaceForProjectRoot` (fn)

Returns the default API namespace suffix for a project root.

```zig
pub fn defaultNamespaceForProjectRoot(arena: std.mem.Allocator, project_root: []const u8) ![]const u8 {
```
