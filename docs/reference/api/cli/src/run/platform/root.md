# `cli/src/run/platform/root.zig`

_Language: Zig_

Platform-specific run pipeline (`ios` / `android`).

This module is the orchestrator entrypoint used by unified run mode.
It delegates option parsing, codegen preflight, and platform execution to
focused modules to keep behavior maintainable and testable.

## Public API

### `types` (const)

No declaration docs available.

```zig
pub const types = @import("types.zig");
```

### `run` (fn)

Executes platform run pipeline (`ios` or `android`) with parsed options.

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

### `runWithOptions` (fn)

Executes platform run pipeline for already-normalized options.

Unified run uses this typed entrypoint to avoid hidden string flag
protocols between orchestration layers.

```zig
pub fn runWithOptions(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    options: types.RunOptions,
) !void {
```

### `printUsage` (fn)

Writes platform run usage help.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
