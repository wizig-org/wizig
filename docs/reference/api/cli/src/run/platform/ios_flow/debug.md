# `cli/src/run/platform/ios_flow/debug.zig`

_Language: Zig_

Debugger attachment helpers for iOS runs.

## Public API

### `attachDebuggerIfNeeded` (fn)

Attaches the requested debugger or prints the no-debugger completion message.

```zig
pub fn attachDebuggerIfNeeded(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    debugger_mode: types.DebuggerMode,
    pid: u64,
) !void {
```
