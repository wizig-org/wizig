# `cli/src/commands/plugin/root/sync.zig`

_Language: Zig_

Plugin registry synchronization for `wizig plugin sync`.

## Public API

### `run` (fn)

Scans plugin manifests, writes generated registrants, and refreshes managed blocks.

```zig
pub fn run(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root_raw: []const u8,
) !void {
```
