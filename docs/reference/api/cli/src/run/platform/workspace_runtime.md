# `cli/src/run/platform/workspace_runtime.zig`

_Language: Zig_

Runtime/workspace resolution for Wizig FFI builds.

This module resolves which runtime source tree should be used for FFI build
steps and returns canonical input paths for incremental fingerprinting.

## Public API

### `resolveFfiBuildInputs` (fn)

Resolves all source inputs needed to build Wizig FFI artifacts.

```zig
pub fn resolveFfiBuildInputs(
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    parent_environ_map: *const std.process.Environ.Map,
    project_root: []const u8,
) !types.FfiBuildInputs {
```

### `resolveWizigWorkspaceRoot` (fn)

Resolves the runtime workspace root from app-local, env, or host hints.

```zig
pub fn resolveWizigWorkspaceRoot(
    arena: Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    project_dir: []const u8,
    stderr: *Io.Writer,
) ![]const u8 {
```
