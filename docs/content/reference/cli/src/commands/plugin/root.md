# `cli/src/commands/plugin/root.zig`

`wizig plugin` command handlers for validation, syncing, and adding plugins.

## Public API

### `run` (fn)

Executes plugin subcommands.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
```

### `printUsage` (fn)

Writes usage help for the plugin command.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
