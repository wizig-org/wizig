# `cli/src/commands/self_update.zig`

_Language: Zig_

`wizig self-update` — checks for and installs the latest release.

## Public API

### `run` (fn)

No declaration docs available.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
) !void {
```

### `printUsage` (fn)

No declaration docs available.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
