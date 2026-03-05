# `cli/src/commands/codegen/watch/runner.zig`

_Language: Zig_

Long-running watch loop for incremental code generation.

## Responsibilities
- Poll source/contract state on a fixed interval.
- Trigger codegen only when the watch fingerprint changes.
- Keep running on recoverable errors so IDE editing remains smooth.

## Integration Model
The runner receives callback functions for:
- resolving the active API contract path
- executing code generation

This keeps the watch loop decoupled from `codegen/root.zig` internals.

## Public API

### `ResolveApiPathFn` (const)

Callback used to resolve the currently active contract path.

The callback should return:
- `null` when discovery mode is active
- non-null absolute path when a contract is active

```zig
pub const ResolveApiPathFn = *const fn (
```

### `GenerateProjectFn` (const)

Callback used to execute a single codegen pass.

```zig
pub const GenerateProjectFn = *const fn (
```

### `runWatchCodegenLoop` (fn)

Runs the incremental watch loop until externally interrupted.

Behavior summary:
- Initial pass runs immediately.
- Subsequent passes run only on fingerprint changes.
- On generation failure, the loop waits for another change.

```zig
pub fn runWatchCodegenLoop(
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    api_override: ?[]const u8,
    watch_interval_ms: u64,
    resolve_api_path_fn: ResolveApiPathFn,
    generate_project_fn: GenerateProjectFn,
) !void {
```
