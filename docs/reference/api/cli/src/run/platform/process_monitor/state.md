# `cli/src/run/platform/process_monitor/state.zig`

_Language: Zig_

Synchronization state for monitored child process wait handling.

## Public API

### `WaitState` (const)

Shared state used by the wait thread and watchdog loop.

```zig
pub const WaitState = struct {
```

### `WaitStateSnapshot` (const)

Immutable snapshot of the shared wait state.

```zig
pub const WaitStateSnapshot = struct {
```

### `WaitThreadContext` (const)

Wait-thread context used to watch the inherited child process.

```zig
pub const WaitThreadContext = struct {
```

### `waitForChildThread` (fn)

Waits for the child process on a helper thread and records the result.

```zig
pub fn waitForChildThread(ctx: *WaitThreadContext) void {
```

### `readWaitState` (fn)

Returns a consistent snapshot of the wait state under lock.

```zig
pub fn readWaitState(state: *WaitState) WaitStateSnapshot {
```

### `waitForChildState` (fn)

Waits for a child state transition until the timeout elapses.

```zig
pub fn waitForChildState(io: std.Io, state: *WaitState, timeout_seconds: u64) bool {
```
