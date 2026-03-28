# `src/cli/commands/codegen/root/output_plan.zig`

_Language: Zig_

Generated output path planning for codegen.

## Public API

### `OutputPlan` (const)

Filesystem plan for generated code and SDK mirror outputs.

```zig
pub const OutputPlan = struct {
```

### `prepare` (fn)

Resolves output paths and ensures the generated directories exist.

```zig
pub fn prepare(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
) !OutputPlan {
```
