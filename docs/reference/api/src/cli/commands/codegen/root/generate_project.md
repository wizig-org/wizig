# `src/cli/commands/codegen/root/generate_project.zig`

_Language: Zig_

High-level orchestration for one complete codegen pass.

## Public API

### `generateProject` (fn)

Generates project bindings, synchronizes host artifacts, and prints the summary.

```zig
pub fn generateProject(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
) !void {
```
