# `cli/src/commands/plugin/root/add.zig`

_Language: Zig_

Plugin import flow for `wizig plugin add`.

## Public API

### `run` (fn)

Adds a plugin from a git source or a local filesystem path.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    source_path: []const u8,
    project_root_raw: []const u8,
) !void {
```
