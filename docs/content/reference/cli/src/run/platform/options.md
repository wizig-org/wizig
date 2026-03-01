# `cli/src/run/platform/options.zig`

_Language: Zig_

Parsing and normalization for `wizig run` platform options.

The parser enforces platform-specific flag validity and keeps all option
validation in one module so execution paths can assume normalized input.

## Public API

### `parseRunOptions` (fn)

Parses CLI arguments into a validated `RunOptions` object.

```zig
pub fn parseRunOptions(args: []const []const u8, stderr: *Io.Writer) !types.RunOptions {
```

### `normalizeRunOptions` (fn)

Normalizes run options that depend on filesystem context.

```zig
pub fn normalizeRunOptions(arena: Allocator, io: std.Io, options: types.RunOptions) !types.RunOptions {
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
    arena: Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    mode: types.DebuggerMode,
) !types.DebuggerMode {
```
