# `cli/src/commands/create/root.zig`

`wizig create` command parser and dispatch.

## Public API

### `run` (fn)

Parses create options and delegates scaffold generation.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
```

### `printUsage` (fn)

Writes usage help for the create command.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
