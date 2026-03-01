# `cli/src/run/unified/root.zig`

_Language: Zig_

Unified run orchestration entrypoint.

Unified mode discovers available iOS/Android targets, selects one, logs
run metadata, then delegates concrete execution to platform runners.

## Public API

### `run` (fn)

Discovers available targets and runs the selected host flow.

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

Writes unified run usage help.

```zig
pub fn printUsage(writer: *Io.Writer) Io.Writer.Error!void {
```
