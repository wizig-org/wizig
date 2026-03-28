# `src/cli/commands/codegen/root/output_write.zig`

_Language: Zig_

Rendering and file persistence for generated code outputs.

## Public API

### `WriteResult` (const)

Change summary for generated files written in one codegen pass.

```zig
pub const WriteResult = struct {
```

### `renderAndWrite` (fn)

Renders all generated outputs and persists them to disk.

```zig
pub fn renderAndWrite(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    project_root: []const u8,
    plan: output_plan.OutputPlan,
    bundle: spec_bundle.SpecBundle,
) !WriteResult {
```
