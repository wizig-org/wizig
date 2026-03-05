# `cli/src/commands/codegen/contract/resolve.zig`

_Language: Zig_

Contract path resolution from CLI override or project defaults.

## Public API

### `resolveApiContract` (fn)

No declaration docs available.

```zig
pub fn resolveApiContract(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
) !?source.ResolvedApiContract {
```
