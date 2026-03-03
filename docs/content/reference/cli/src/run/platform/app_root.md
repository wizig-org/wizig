# `cli/src/run/platform/app_root.zig`

_Language: Zig_

App-root path normalization for platform run flows.

## Problem
Platform execution code receives run paths from different entrypoints:
- app root (`<app>`)
- host directory (`<app>/ios`, `<app>/android`)

Downstream codegen and FFI preparation must always operate against app root.

## Strategy
- Trim trailing separators to avoid dirname edge cases.
- Detect whether the provided path already looks like app root (`lib/` exists).
- Otherwise fall back to parent directory.

## Public API

### `resolveAppRoot` (fn)

Resolves app root from a normalized run path.

Returns:
- original path when it already matches an app root
- parent path when run was initiated from a host directory

```zig
pub fn resolveAppRoot(
    arena: std.mem.Allocator,
    io: std.Io,
    run_project_dir: []const u8,
) ![]const u8 {
```
