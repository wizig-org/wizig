# `src/cli/commands/plugin/root/dispatch.zig`

_Language: Zig_

Parses `wizig plugin` arguments and routes them to subcommand handlers.

## Public API

### `Command` (const)

Parsed plugin subcommands.

```zig
pub const Command = union(enum) {
```

### `run` (fn)

Parses the plugin command arguments and executes the requested handler.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
```

### `parse` (fn)

Returns a typed plugin command or reports argument validation failures.

```zig
pub fn parse(args: []const []const u8, stderr: *Io.Writer) !Command {
```
