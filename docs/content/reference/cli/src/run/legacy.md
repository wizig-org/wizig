# `cli/src/run/legacy.zig`

Platform-specific run pipeline used by unified run selection.

## Public API

### `RunError` (const)

Public run command error set.

```zig
pub const RunError = error{RunFailed};
```

### `run` (fn)

Executes platform run pipeline (`ios` or `android`) with parsed options.

```zig
pub fn run(
    arena: Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
```

### `printUsage` (fn)

Writes legacy platform run usage help.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
