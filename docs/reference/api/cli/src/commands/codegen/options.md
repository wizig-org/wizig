# `cli/src/commands/codegen/options.zig`

_Language: Zig_

Codegen command-line option parsing.

## Responsibilities
- Parse `wizig codegen` CLI arguments into a normalized options struct.
- Validate numeric watch settings with user-facing diagnostics.
- Keep parsing concerns separate from generation and watch-loop execution.

## Design Notes
- This module is intentionally small and self-contained so option behavior
can evolve without touching the large generator implementation.
- Parsing returns explicit `error.InvalidArguments` on user input issues.

## Public API

### `default_watch_interval_ms` (const)

Default watch polling interval in milliseconds.

```zig
pub const default_watch_interval_ms: u64 = 500;
```

### `CodegenOptions` (const)

Normalized options for `wizig codegen`.

Field semantics:
- `project_root`: App root path to generate into.
- `api_override`: Explicit contract path (`--api`) when provided.
- `watch`: Enables continuous incremental codegen loop.
- `watch_interval_ms`: Polling interval used only in watch mode.

```zig
pub const CodegenOptions = struct {
```

### `parseCodegenOptions` (fn)

Parses raw CLI arguments into `CodegenOptions`.

Supported forms:
- Positional: `[project_root]`
- Contract: `--api <path>` or `--api=<path>`
- Watch: `--watch`
- Interval: `--watch-interval-ms <n>` or `--watch-interval-ms=<n>`

```zig
pub fn parseCodegenOptions(args: []const []const u8, stderr: *Io.Writer) !CodegenOptions {
```
