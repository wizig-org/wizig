# `cli/src/run/platform/process_monitor/term.zig`

_Language: Zig_

Child termination helpers shared by monitor and supervisor logic.

## Public API

### `termIsSuccess` (fn)

Returns whether a process terminated with successful exit code.

```zig
pub fn termIsSuccess(term: std.process.Child.Term) bool {
```

### `termIsInterrupted` (fn)

Returns whether a process terminated due to user interrupt signal.

```zig
pub fn termIsInterrupted(term: std.process.Child.Term) bool {
```

### `termLabel` (fn)

Returns a compact label for a child termination state.

```zig
pub fn termLabel(term: std.process.Child.Term) []const u8 {
```
