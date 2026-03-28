# `src/cli/commands/plugin/root/dispatch.zig`

_Language: Zig_

`wizig plugin` clap-backed subcommand dispatch.

## Public API

### `run` (fn)

Parses plugin arguments and executes the selected subcommand.

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

Writes plugin command usage text.

```zig
pub fn printUsage(writer: *Io.Writer) !void {
```

### `parseSyncProjectRoot` (fn)

No declaration docs available.

```zig
pub fn parseSyncProjectRoot(allocator: std.mem.Allocator, stderr: *Io.Writer, args: []const []const u8) !?[]const u8 {
```

### `parseAddArgs` (fn)

No declaration docs available.

```zig
pub fn parseAddArgs(allocator: std.mem.Allocator, stderr: *Io.Writer, args: []const []const u8) !?AddArgs {
```
