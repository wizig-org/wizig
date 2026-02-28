# `cli/src/run.zig`

Shared run command entrypoint that forwards to unified runner.

## Public API

### `RunError` (const)

Top-level run command errors.

```zig
pub const RunError = error{RunFailed};
```

### `run` (fn)

Executes unified run flow for project hosts/devices.

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

Writes run command usage text.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
