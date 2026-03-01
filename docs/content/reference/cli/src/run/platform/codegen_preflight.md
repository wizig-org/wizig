# `cli/src/run/platform/codegen_preflight.zig`

_Language: Zig_

Code generation preflight for platform run commands.

The platform runner reuses codegen logic so host-side bindings remain in
sync with current app sources before build/install operations.

## Public API

### `runCodegenPreflight` (fn)

Ensures app bindings are generated before platform build execution.

```zig
pub fn runCodegenPreflight(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    host_project_dir: []const u8,
) !void {
```
