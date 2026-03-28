# `src/cli/run/unified/root.zig`

_Language: Zig_

Unified run orchestration entrypoint.

## Public API

### `run` (fn)

No declaration docs available.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    args: []const []const u8,
) !void {
```

### `printUsage` (fn)

No declaration docs available.

```zig
pub fn printUsage(writer: *Io.Writer) !void {
```
