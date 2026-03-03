# `cli/src/commands/plugin/root.zig`

_Language: Zig_

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

No declaration docs available.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
