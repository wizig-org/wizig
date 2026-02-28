# `cli/src/run/unified.zig`

Unified run mode that auto-detects iOS/Android hosts and devices.

## Public API

### `run` (fn)

Discovers available targets and runs the selected host flow.

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

Writes unified run usage help.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
