# `cli/src/run/unified.zig`

_Language: Zig_

Unified run module shim.

This file intentionally remains small and delegates implementation details to
`run/unified/*` modules to keep the run pipeline maintainable.

## Public API

### `run` (fn)

Discovers available targets and runs the selected host flow.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
```

### `printUsage` (fn)

Writes unified run usage help.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
