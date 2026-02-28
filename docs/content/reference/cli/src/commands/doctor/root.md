# `cli/src/commands/doctor/root.zig`

`ziggy doctor` diagnostics for host tools and bundled assets.

## Public API

### `run` (fn)

Runs environment diagnostics and SDK integrity checks.

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

Writes usage help for the doctor command.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
