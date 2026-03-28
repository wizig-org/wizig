# `src/cli/commands/plugin/root.zig`

_Language: Zig_

Public `wizig plugin` entrypoint.

The command implementation lives under `commands/plugin/root/` so the
top-level module stays small and preserves the existing CLI surface.

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

Writes the plugin command usage block used by the top-level help output.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
