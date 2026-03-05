# `cli/src/commands/uninstall.zig`

_Language: Zig_

`wizig uninstall` — removes the wizig installation.

## Public API

### `run` (fn)

No declaration docs available.

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
