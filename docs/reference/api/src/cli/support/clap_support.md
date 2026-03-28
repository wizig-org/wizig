# `src/cli/support/clap_support.zig`

_Language: Zig_

Shared zig-clap helpers for slice-based CLI parsing.

## Public API

### `SliceIterator` (const)

Lightweight iterator adapter for `[]const []const u8` argument slices.

```zig
pub const SliceIterator = struct {
```

### `init` (fn)

Creates an iterator over a borrowed argument slice.

```zig
    pub fn init(args: []const []const u8) SliceIterator {
```

### `next` (fn)

Returns the next argument or `null` when exhausted.

```zig
    pub fn next(self: *SliceIterator) ?[]const u8 {
```

### `remaining` (fn)

Returns the unconsumed suffix after partial parsing.

```zig
    pub fn remaining(self: *const SliceIterator) []const []const u8 {
```

### `reportDiagnostic` (fn)

Prints a clap diagnostic to stderr and flushes immediately.

```zig
pub fn reportDiagnostic(stderr: *Io.Writer, diag: clap.Diagnostic, err: anyerror) !void {
```

### `writeUsageLine` (fn)

Writes a one-line usage string prefixed with the command invocation.

```zig
pub fn writeUsageLine(
    writer: *Io.Writer,
    prefix: []const u8,
    comptime params: []const clap.Param(clap.Help),
) !void {
```

### `writeOptionsBlock` (fn)

Writes an options block generated from the clap parameter specification.

```zig
pub fn writeOptionsBlock(
    writer: *Io.Writer,
    comptime params: []const clap.Param(clap.Help),
) !void {
```
