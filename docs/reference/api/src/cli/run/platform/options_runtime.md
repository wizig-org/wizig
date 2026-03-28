# `src/cli/run/platform/options_runtime.zig`

_Language: Zig_

Runtime helpers for parsed `wizig run <platform>` options.

## Public API

### `normalizeRunOptions` (fn)

Normalizes run options that depend on filesystem context.

```zig
pub fn normalizeRunOptions(arena: std.mem.Allocator, io: std.Io, options: types.RunOptions) !types.RunOptions {
```

### `resolveIosDebugger` (fn)

Resolves iOS debugger mode with platform constraints.

```zig
pub fn resolveIosDebugger(stderr: *Io.Writer, mode: types.DebuggerMode) !types.DebuggerMode {
```

### `resolveAndroidDebugger` (fn)

Resolves Android debugger mode and validates required host tools.

```zig
pub fn resolveAndroidDebugger(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    mode: types.DebuggerMode,
) !types.DebuggerMode {
```

### `validatePlatformOptions` (fn)

Validates platform-specific flag combinations.

```zig
pub fn validatePlatformOptions(stderr: *Io.Writer, options: types.RunOptions) !void {
```
