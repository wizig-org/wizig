# `cli/src/commands/run/root.zig`

`wizig run` command shim.

## Public API

### `run` (fn)

Delegates run command handling to the shared run module.

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

Writes usage help for the run command.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
