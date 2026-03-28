# `cli/src/commands/plugin/root/validate.zig`

_Language: Zig_

Validation flow for `wizig plugin validate`.

## Public API

### `run` (fn)

Reads a plugin manifest, validates it, and prints a summary.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    file_path: []const u8,
) !void {
```
