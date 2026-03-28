# `cli/src/commands/codegen/root/spec_bundle.zig`

_Language: Zig_

Shared codegen input resolution and project-spec assembly.

## Public API

### `SpecBundle` (const)

Fully resolved inputs required by downstream codegen stages.

```zig
pub const SpecBundle = struct {
```

### `build` (fn)

Resolves the contract source, discovered project API, and compatibility metadata.

```zig
pub fn build(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    api_path: ?[]const u8,
) !SpecBundle {
```
